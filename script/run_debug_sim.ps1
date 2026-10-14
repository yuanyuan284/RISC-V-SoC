param([switch]$CompileOnly, [ValidateSet('remote','uart')][string]$Test = 'remote')
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/debug'
$stage3 = Join-Path $root 'build/stage3'
$cpu = Join-Path $root 'build/cpu-debug/VexRiscvDebug.v'
if (!(Test-Path $cpu)) { throw 'Run build_debug_cpu.ps1 first' }
New-Item -ItemType Directory -Path $build -Force | Out-Null
& $Python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model generation failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_debug --cpu $cpu
if ($LASTEXITCODE) { throw 'UART source preparation failed' }
$top = if ($Test -eq 'remote') { 'tb_debug_remote' } else { 'tb_debug_uart' }
$image = Join-Path $build "$Test.vvp"
$sources = @((Join-Path $root "tb/stage3/$top.v"),
    (Join-Path $root 'rtl/stage3/stage3_debug_top.v'), $cpu,
    (Join-Path $stage3 'stage3_memory_sim.v'),
    (Join-Path $stage3 'bram_functional_models.v'),
    (Join-Path $root 'rtl/common/fifo.v'))
foreach ($name in @('rx','tx','wb')) { $sources += Join-Path $build "uart_${name}_stage2.v" }
& $Iverilog -g2012 -I $stage3 -s $top -o $image @sources
if ($LASTEXITCODE) { throw 'Debug SoC compilation failed' }
if (!$CompileOnly) {
    if ($Test -eq 'remote') {
        & $Python (Join-Path $PSScriptRoot 'debug_remote_sim.py') --vvp $Vvp
        if ($LASTEXITCODE) { throw 'Debug JTAG simulation failed' }
    } else {
        Push-Location $stage3
        try {
            & $Vvp $image
            if ($LASTEXITCODE) { throw 'Debug UART boot simulation failed' }
        } finally { Pop-Location }
    }
}
