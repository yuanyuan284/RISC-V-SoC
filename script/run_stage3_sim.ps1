param([ValidateSet('memory','smoke','uart','boundary-header','boundary')][string]$Test = 'memory',
      [switch]$CompileOnly, [switch]$Waves)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build\stage3'
New-Item -ItemType Directory -Path $build -Force | Out-Null
& $python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model preparation failed' }
$top = if ($Test -eq 'memory') { 'tb_stage3_memory' } else { 'tb_stage3_uart' }
$sources = @((Join-Path $root "tb\stage3\$top.v"),
    (Join-Path $build 'stage3_memory_sim.v'), (Join-Path $build 'bram_functional_models.v'))
if ($Test -ne 'memory') {
    & $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_uart --cpu $VexRiscvSource
    if ($LASTEXITCODE) { throw 'UART source preparation failed' }
    if (!(Test-Path (Join-Path $root 'build/stage2/app_a.bin'))) {
        & (Join-Path $PSScriptRoot 'build_stage2_firmware.ps1')
    }
    & $Python (Join-Path $PSScriptRoot 'prepare_stage3_test_frames.py')
    if ($LASTEXITCODE) { throw 'Test frame preparation failed' }
    $sources += @((Join-Path $root 'rtl\stage3\stage3_top.v'),
        $VexRiscvSource,
        (Join-Path $root 'rtl\common\fifo.v'))
    $sources += @('uart_wb_stage2.v','uart_rx_stage2.v','uart_tx_stage2.v') | ForEach-Object {
        Join-Path $build $_
    }
}
Push-Location $build
try {
    & $Iverilog '-g2012' '-I' $build '-s' $top '-o' "$Test.vvp" @sources
    if ($LASTEXITCODE) { throw 'Stage-3 Verilog compilation failed' }
    if ($CompileOnly) { return }
    $options = @()
    if ($Test -eq 'smoke') { $options += '+SMOKE' }
    if ($Test -eq 'boundary-header') { $options += '+BOUNDARY_HEADER' }
    if ($Test -eq 'boundary') { $options += '+BOUNDARY' }
    if ($Waves) { $options += '+WAVE' }
    & $Vvp "$Test.vvp" @options
    if ($LASTEXITCODE) { throw "Stage-3 $Test simulation failed" }
} finally { Pop-Location }
