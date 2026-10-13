param([ValidateSet('memory','smoke','uart')][string]$Test = 'memory')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'stage3\build'
$python = 'C:\Users\yuanj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$env:PATH = "D:\risc-v\simulator\ucrt64\bin;$env:PATH"
& $python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM model preparation failed' }
& $python (Join-Path $PSScriptRoot 'prepare_stage3_test_frames.py')
if ($LASTEXITCODE) { throw 'Test frame preparation failed' }
$top = if ($Test -eq 'memory') { 'tb_stage3_memory' } else { 'tb_stage3_uart' }
$sources = @((Join-Path $root "stage3\sim\$top.v"),
    (Join-Path $build 'stage3_memory_sim.v'), (Join-Path $build 'bram_functional_models.v'))
if ($Test -ne 'memory') {
    $sources += @((Join-Path $root 'stage3\rtl\stage3_top.v'),
        'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v',
        (Join-Path $root 'user_source\hdl_source\fifo.v'))
    $sources += @('uart_wb_stage2.v','uart_rx_stage2.v','uart_tx_stage2.v') | ForEach-Object {
        Join-Path $root "stage2\build\$_"
    }
}
Push-Location $build
try {
    & 'D:\risc-v\simulator\ucrt64\bin\iverilog.exe' '-g2012' '-I' $build '-s' $top '-o' "$Test.vvp" @sources
    if ($LASTEXITCODE) { throw 'Stage-3 Verilog compilation failed' }
    $options = if ($Test -eq 'smoke') { @('+SMOKE') } else { @() }
    & 'D:\risc-v\simulator\ucrt64\bin\vvp.exe' "$Test.vvp" @options
    if ($LASTEXITCODE) { throw "Stage-3 $Test simulation failed" }
} finally { Pop-Location }
