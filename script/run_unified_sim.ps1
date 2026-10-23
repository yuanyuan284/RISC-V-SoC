param([ValidateSet('start','system','jtag','jtag-bootrom','bootrom','bootrom-reject')][string]$Test = 'start',
      [switch]$CompileOnly, [switch]$Progress, [switch]$DirectXip,
      [int]$Timeout = 600)
. (Join-Path $PSScriptRoot 'common.ps1')
$helloTest = $Test -eq 'bootrom' -or $Test -eq 'bootrom-reject'
if ($helloTest -and $DirectXip) {
    throw 'BootROM test must use the default reset vector, not -DirectXip'
}
if ($Test -eq 'jtag-bootrom' -and $DirectXip) {
    throw 'JTAG BootROM test must use the default reset vector, not -DirectXip'
}
$build = Join-Path $root 'build/unified'
$cpu = Join-Path $root 'build/cpu-unified/VexRiscvUnified.v'
if (!(Test-Path $cpu)) { throw 'Run build_debug_cpu.ps1 -Variant unified first' }
& $Python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model preparation failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_unified --cpu $cpu
if ($LASTEXITCODE) { throw 'Unified source preparation failed' }
$imageDir = if ($helloTest) { Join-Path $root 'build/flash' } else { $build }
$imageName = if ($helloTest) { 'hello.xip' } else { 'freertos_xip.xip' }
$image = Join-Path $imageDir $imageName
if (!(Test-Path $image) -or !(Test-Path "$image.hex")) {
    $buildCommand = if ($helloTest) { 'build_flash_firmware.ps1' } else { 'build_unified_firmware.ps1' }
    throw "Run $buildCommand first"
}
$imageBytes = (Get-Item $image).Length
if ($Test -eq 'jtag-bootrom') {
    & $Python (Join-Path $PSScriptRoot 'prepare_unified_sim_image.py')
    if ($LASTEXITCODE) { throw 'Simulation-only fast CRC image preparation failed' }
}
$sources = @((Join-Path $root 'tb/stage3/tb_unified_xip.v'),
    (Join-Path $root 'rtl/stage3/stage3_unified_top.v'), $cpu,
    (Join-Path $root 'rtl/stage3/stage3_flash_read.v'),
    (Join-Path $root 'rtl/stage3/stage3_flash_writer.v'),
    (Join-Path $root 'rtl/stage3/rtos_clint.v'),
    (Join-Path $root 'rtl/stage3/rtos_plic.v'),
    (Join-Path $root 'rtl/stage3/rtos_event.v'),
    (Join-Path $root 'rtl/common/fifo.v'),
    (Join-Path $root 'build/stage3/stage3_memory_sim.v'),
    (Join-Path $root 'build/stage3/bram_functional_models.v'))
$sources += @('uart_wb_stage2.v','uart_rx_stage2.v','uart_tx_stage2.v') | ForEach-Object { Join-Path $build $_ }
$compileOptions = @('-g2012', '-I', (Join-Path $root 'build/flash'),
                    '-s', 'tb_unified_xip')
if ($DirectXip -or $Test -eq 'jtag') {
    $compileOptions += '-Ptb_unified_xip.DIRECT_XIP=1'
}
if ($Test -eq 'jtag' -or $Test -eq 'jtag-bootrom') {
    $compileOptions += '-Ptb_unified_xip.REMOTE_JTAG=1'
}
if ($Test -eq 'jtag-bootrom') {
    $compileOptions += '-Ptb_unified_xip.JTAG_AFTER_SELFTEST=1'
}
if ($helloTest) {
    $compileOptions += '-Ptb_unified_xip.HELLO_IMAGE=1'
}
& $Iverilog @compileOptions '-o' (Join-Path $build 'unified_xip.vvp') @sources
if ($LASTEXITCODE) { throw 'Unified XIP RTL compilation failed' }
if ($CompileOnly) { return }
if ($Test -eq 'jtag' -or $Test -eq 'jtag-bootrom') {
    $openocd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
    $validationArgs = @('--openocd', $openocd, '--vvp', $Vvp, '--timeout', $Timeout)
    if ($Test -eq 'jtag-bootrom') { $validationArgs += '--bootrom' }
    & $Python (Join-Path $PSScriptRoot 'validate_unified_jtag_sim.py') @validationArgs
    if ($LASTEXITCODE) { throw 'Unified XIP JTAG simulation failed' }
    return
}
Push-Location $build
try {
    $options = @("+image_bytes=$imageBytes")
    if ($Test -eq 'start' -or $helloTest) { $options += '+START_ONLY' }
    if ($Test -eq 'bootrom-reject') { $options += '+BAD_CRC' }
    if ($Progress) { $options += '+PROGRESS' }
    & $Vvp 'unified_xip.vvp' @options
    if ($LASTEXITCODE) { throw "Unified XIP $Test simulation failed" }
} finally { Pop-Location }
