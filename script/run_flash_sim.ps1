. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/flash'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$image = Join-Path $build 'tb_flash_read.vvp'
& $Iverilog -g2012 -s tb_flash_read -o $image `
    (Join-Path $root 'rtl/stage3/stage3_flash_read.v') `
    (Join-Path $root 'tb/stage3/tb_flash_read.v')
if ($LASTEXITCODE) { throw 'Flash RTL compilation failed' }
& $Vvp $image
if ($LASTEXITCODE) { throw 'Flash RTL simulation failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model generation failed' }
$stage3 = Join-Path $root 'build/stage3'
$cpu = Join-Path $root 'build/cpu-debug/VexRiscvDebug.v'
if (!(Test-Path $cpu)) { throw 'Run build_debug_cpu.ps1 first' }
if (!(Test-Path (Join-Path $build 'hello.xip.hex'))) {
    throw 'Run build_flash_firmware.ps1 first'
}
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_flash --cpu $cpu
if ($LASTEXITCODE) { throw 'Flash source preparation failed' }
$socImage = Join-Path $build 'tb_flash_soc.vvp'
$sources = @((Join-Path $root 'tb/stage3/tb_flash_soc.v'),
    (Join-Path $root 'rtl/stage3/stage3_debug_top.v'),
    (Join-Path $root 'rtl/stage3/stage3_flash_read.v'), $cpu,
    (Join-Path $stage3 'stage3_memory_sim.v'),
    (Join-Path $stage3 'bram_functional_models.v'),
    (Join-Path $root 'rtl/common/fifo.v'))
foreach ($name in @('rx','tx','wb')) {
    $sources += Join-Path $build "uart_${name}_stage2.v"
}
& $Iverilog -g2012 -I $build -s tb_flash_soc -o $socImage @sources
if ($LASTEXITCODE) { throw 'Flash SoC compilation failed' }
Push-Location $build
try {
    & $Vvp $socImage
    if ($LASTEXITCODE) { throw 'Flash SoC simulation failed' }
} finally { Pop-Location }
