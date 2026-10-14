$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build\stage2'
& (Join-Path $PSScriptRoot 'build_stage2_td.ps1') -PrepareOnly -Jtag
foreach ($app in @('app_a', 'app_b')) {
    & $python (Join-Path $PSScriptRoot 'elf_to_hex.py') `
        (Join-Path $build "$app.elf") (Join-Path $build "${app}_from_elf.hex")
    if ($LASTEXITCODE) { throw "ELF conversion failed for $app" }
}
$source = @(
    (Join-Path $root 'tb\stage2\tb_stage2_jtag.v'),
    (Join-Path $build 'stage2_top.v'),
    (Join-Path $root 'rtl\stage2\stage2_memory.v'),
    (Join-Path $root 'rtl\common\jtag_wb_loader.v'),
    $VexRiscvSource,
    (Join-Path $build 'uart_wb_stage2.v'),
    (Join-Path $root 'rtl\common\fifo.v'),
    (Join-Path $build 'uart_rx_stage2.v'),
    (Join-Path $build 'uart_tx_stage2.v')
)
Push-Location $build
try {
    & $Iverilog `
        '-g2012' '-s' 'tb_stage2_jtag' '-o' 'stage2_jtag_test.vvp' @source
    if ($LASTEXITCODE) { throw 'JTAG SoC Verilog compilation failed' }
    & $Vvp 'stage2_jtag_test.vvp'
    if ($LASTEXITCODE) { throw 'JTAG SoC simulation failed' }
} finally { Pop-Location }
