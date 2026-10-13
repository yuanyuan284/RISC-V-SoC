$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'stage2\build'
$python = 'C:\Users\yuanj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
foreach ($app in @('app_a', 'app_b')) {
    & $python (Join-Path $PSScriptRoot 'elf_to_hex.py') `
        (Join-Path $build "$app.elf") (Join-Path $build "${app}_from_elf.hex")
    if ($LASTEXITCODE) { throw "ELF conversion failed for $app" }
}
$env:PATH = "D:\risc-v\simulator\ucrt64\bin;$env:PATH"
$source = @(
    (Join-Path $root 'stage2\sim\tb_stage2_jtag.v'),
    (Join-Path $root 'stage2\rtl\stage2_top.v'),
    (Join-Path $root 'stage2\rtl\stage2_memory.v'),
    (Join-Path $root 'user_source\hdl_source\jtag_wb_loader.v'),
    'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v',
    (Join-Path $build 'uart_wb_stage2.v'),
    (Join-Path $root 'user_source\hdl_source\fifo.v'),
    (Join-Path $build 'uart_rx_stage2.v'),
    (Join-Path $build 'uart_tx_stage2.v')
)
Push-Location $build
try {
    & 'D:\risc-v\simulator\ucrt64\bin\iverilog.exe' `
        '-g2012' '-s' 'tb_stage2_jtag' '-o' 'stage2_jtag_test.vvp' @source
    if ($LASTEXITCODE) { throw 'JTAG SoC Verilog compilation failed' }
    & 'D:\risc-v\simulator\ucrt64\bin\vvp.exe' 'stage2_jtag_test.vvp'
    if ($LASTEXITCODE) { throw 'JTAG SoC simulation failed' }
} finally { Pop-Location }
