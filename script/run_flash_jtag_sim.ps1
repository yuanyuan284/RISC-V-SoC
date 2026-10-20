. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/flash'
$stage3 = Join-Path $root 'build/stage3'
$cpu = Join-Path $root 'build/cpu-debug/VexRiscvDebug.v'
$OpenOcd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
if (!(Test-Path $cpu)) { throw 'Run build_debug_cpu.ps1 first' }
if (!(Test-Path (Join-Path $build 'hello.xip'))) {
    throw 'Run build_flash_firmware.ps1 first'
}
& $Python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model generation failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_flash --cpu $cpu
if ($LASTEXITCODE) { throw 'Flash source preparation failed' }
$sources = @((Join-Path $root 'tb/stage3/tb_flash_remote.v'),
    (Join-Path $root 'rtl/stage3/stage3_debug_top.v'),
    (Join-Path $root 'rtl/stage3/stage3_flash_read.v'), $cpu,
    (Join-Path $stage3 'stage3_memory_sim.v'),
    (Join-Path $stage3 'bram_functional_models.v'),
    (Join-Path $root 'rtl/common/fifo.v'))
foreach ($name in @('rx','tx','wb')) {
    $sources += Join-Path $build "uart_${name}_stage2.v"
}
& $Iverilog -g2012 -I $build -s tb_flash_remote -o (Join-Path $build 'flash-remote.vvp') @sources
if ($LASTEXITCODE) { throw 'Flash JTAG simulator compilation failed' }
& $Python (Join-Path $PSScriptRoot 'validate_flash_jtag_sim.py') --openocd $OpenOcd --vvp $Vvp
if ($LASTEXITCODE) { throw 'Flash OpenOCD/JTAG readback simulation failed' }
