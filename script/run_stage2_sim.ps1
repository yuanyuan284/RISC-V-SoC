$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build\stage2'
& (Join-Path $PSScriptRoot 'build_stage2_td.ps1') -PrepareOnly
& $Python (Join-Path $root 'script\prepare_stage2_frames.py')
if ($LASTEXITCODE) { throw 'Frame generation failed' }
$source = @(
    (Join-Path $root 'tb\stage2\tb_stage2_uart.v'),
    (Join-Path $build 'stage2_top.v'),
    (Join-Path $root 'rtl\stage2\stage2_memory.v'),
    $VexRiscvSource
)
$source += @('uart_wb_stage2.v', 'fifo.v', 'uart_rx_stage2.v', 'uart_tx_stage2.v') | ForEach-Object {
    if ($_ -like '*stage2.v') { Join-Path $build $_ }
    else { Join-Path $root "rtl\common\$_" }
}
Push-Location $build
try {
    & $iverilog '-g2012' '-s' 'tb_stage2_uart' '-o' 'stage2_test.vvp' @source
    if ($LASTEXITCODE) { throw 'Verilog compilation failed' }
    & $vvp 'stage2_test.vvp'
    if ($LASTEXITCODE) { throw 'Stage-2 simulation failed' }
} finally { Pop-Location }
