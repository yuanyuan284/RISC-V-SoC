$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'stage2\build'
$env:PATH = "D:\risc-v\simulator\ucrt64\bin;$env:PATH"
$iverilog = 'D:\risc-v\simulator\ucrt64\bin\iverilog.exe'
$vvp = 'D:\risc-v\simulator\ucrt64\bin\vvp.exe'
if (!(Test-Path -LiteralPath $iverilog)) { throw 'Icarus Verilog not found' }
& 'C:\Users\yuanj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' (Join-Path $root 'stage2\sim\prepare_frames.py')
if ($LASTEXITCODE) { throw 'Frame generation failed' }
$source = @(
    (Join-Path $root 'stage2\sim\tb_stage2_uart.v'),
    (Join-Path $root 'stage2\rtl\stage2_top.v'),
    (Join-Path $root 'stage2\rtl\stage2_memory.v'),
    'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v'
)
$source += @('uart_wb_stage2.v', 'fifo.v', 'uart_rx_stage2.v', 'uart_tx_stage2.v') | ForEach-Object {
    if ($_ -like '*stage2.v') { Join-Path $build $_ }
    else { Join-Path $root "user_source\hdl_source\$_" }
}
Push-Location $build
try {
    & $iverilog '-g2012' '-s' 'tb_stage2_uart' '-o' 'stage2_test.vvp' @source
    if ($LASTEXITCODE) { throw 'Verilog compilation failed' }
    & $vvp 'stage2_test.vvp'
    if ($LASTEXITCODE) { throw 'Stage-2 simulation failed' }
} finally { Pop-Location }
