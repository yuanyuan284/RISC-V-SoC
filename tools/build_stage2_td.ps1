param([switch]$PrepareOnly, [switch]$Jtag)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'stage2\build'
$hex = Join-Path $output 'bootrom.hex'
if (!(Test-Path -LiteralPath $hex)) { throw 'Run build_stage2_firmware.ps1 first' }
$template = Join-Path $root 'td_project\demo14_vexriscv_stage1_Runs\syn_1\demo14_vexriscv_stage1.prj'
[xml]$project = (Get-Content -LiteralPath $template -Raw).Replace('UsedInP&R', 'UsedInP&amp;R')
$variant = if ($Jtag) { 'stage2_jtag' } else { 'stage2_uart' }
$project.Project.Name = $variant
$project.Project.TOP_MODULE.MODULE = if ($Jtag) { 'stage2_jtag_top' } else { 'stage2_top' }
$sourceBase = Split-Path $template -Parent
foreach ($node in @($project.SelectNodes('/Project/Source_Files/*/File'))) {
    $path = [System.IO.Path]::GetFullPath((Join-Path $sourceBase $node.GetAttribute('Path')))
    $name = [System.IO.Path]::GetFileName($path)
    if ($name -in @('soc_wb_intercon.v', 'jtag_wb_loader.v', 'jtag_watch.cwc')) {
        $node.ParentNode.RemoveChild($node) | Out-Null
        continue
    }
    switch ($name) {
        'design_top_wrapper.v' { $path = Join-Path $root 'stage2\rtl\stage2_top.v' }
        'wb_ram.v' { $path = Join-Path $root 'stage2\rtl\stage2_memory.v' }
        'VexRiscv.v' { $path = 'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v' }
        'uart_wb.v' {
            $uart = (Get-Content -LiteralPath $path -Raw).Replace("`r`n", "`n")
            $needle = "if (i_reset) begin`n        o_wb_ack <= 1'b0;"
            $replacement = "$needle`n        rx_fifo_r_stb <= 0;`n        tx_fifo_w_stb <= 0;`n        o_wb_dat <= 0;"
            if (!$uart.Contains($needle)) { throw 'UART reset block changed; inspect before patching' }
            $uart = $uart.Replace($needle, $replacement)
            $uart = $uart.Replace("rx_fifo_r_stb <= 1'b1;", "rx_fifo_r_stb <= !i_wb_we && !rx_fifo_empty;")
            $path = Join-Path $output 'uart_wb_stage2.v'
            [System.IO.File]::WriteAllText($path, $uart)
        }
        'uart_rx.v' {
            $uart = Get-Content -LiteralPath $path -Raw
            if (!$uart.Contains('module uart_rx (') -or !$uart.Contains('reg [1:0] state = s_IDLE;')) {
                throw 'UART RX source changed; inspect declaration normalization'
            }
            $uart = $uart.Replace('module uart_rx (', 'module uart_rx #(parameter DATA_WIDTH = 16) (')
            $uart = $uart.Replace('    parameter DATA_WIDTH = 16;', '')
            $uart = $uart.Replace('    reg [1:0] state = s_IDLE;', '    reg [1:0] state;')
            $uart = $uart.Replace('        s_STOP = 2;', "        s_STOP = 2;`r`n    initial state = s_IDLE;")
            $path = Join-Path $output 'uart_rx_stage2.v'
            [System.IO.File]::WriteAllText($path, $uart)
        }
        'uart_tx.v' {
            $uart = Get-Content -LiteralPath $path -Raw
            if (!$uart.Contains('module uart_tx (')) { throw 'UART TX source changed' }
            $uart = $uart.Replace('module uart_tx (', 'module uart_tx #(parameter DATA_WIDTH = 16) (')
            $uart = $uart.Replace('    parameter DATA_WIDTH = 16;', '')
            $path = Join-Path $output 'uart_tx_stage2.v'
            [System.IO.File]::WriteAllText($path, $uart)
        }
        'sys_pll.v' {
            $pll = Get-Content -LiteralPath $path -Raw
            $pll = $pll.Replace('.psdone(open)', '.psdone()')
            $pll = $pll.Replace('.do({open, open, open, open, open, open, open, open})', '.do()')
            $pll = $pll.Replace('wire open;', 'wire [4:0] unused_clocks;')
            $pll = $pll.Replace('{open, open, open, open, open, clk1_out, clk0_buf}', '{unused_clocks, clk1_out, clk0_buf}')
            $path = Join-Path $output 'sys_pll_stage2.v'
            [System.IO.File]::WriteAllText($path, $pll)
        }
    }
    $node.SetAttribute('Path', $path.Replace('\', '/'))
}
$watchers = $project.SelectSingleNode('/Project/Source_Files/CWC_FILE')
if ($watchers) { $watchers.ParentNode.RemoveChild($watchers) | Out-Null }
if ($Jtag) {
    $verilog = $project.SelectSingleNode('/Project/Source_Files/Verilog')
    $file = $verilog.SelectSingleNode('File[1]').CloneNode($true)
    $file.SetAttribute('Path', (Join-Path $root 'user_source\hdl_source\jtag_wb_loader.v').Replace('\', '/'))
    $file.SelectSingleNode('FileInfo/Attr[@Name="CompileOrder"]').SetAttribute('Val', '20')
    $verilog.AppendChild($file) | Out-Null
}
$project.Save((Join-Path $output "$variant.prj"))
if ($PrepareOnly) { return }
Push-Location $output
try {
    $flow = if ($Jtag) { 'stage2_jtag_td.tcl' } else { 'stage2_td.tcl' }
    & 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' (Join-Path $PSScriptRoot $flow)
    if ($LASTEXITCODE) { throw 'Stage-2 TD flow failed' }
    $timing = Get-Content -LiteralPath "$variant.timing" -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Stage-2 timing not closed; do not download the bitstream'
    }
    Write-Host 'Stage-2 bit generated with zero reported setup/hold errors. Hardware behavior still unverified.'
} finally { Pop-Location }
