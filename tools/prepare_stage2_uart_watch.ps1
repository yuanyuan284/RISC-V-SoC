$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'stage2\build'
$uartPath = Join-Path $build 'uart_wb_stage2.v'
$fifoPath = Join-Path $root 'user_source\hdl_source\fifo.v'
$projectPath = Join-Path $build 'stage2_uart.prj'

$uart = Get-Content -LiteralPath $uartPath -Raw
$txPattern = '(?s)fifo(\s*#\s*\([^;]*?\)\s*tx0_fifo\s*\()'
if ([regex]::Matches($uart, $txPattern).Count -ne 1) {
    throw 'Expected exactly one TX FIFO instance'
}
$uart = [regex]::Replace($uart, $txPattern, 'fifo_tx_watch$1')
$watchUartPath = Join-Path $build 'uart_wb_watch.v'
[System.IO.File]::WriteAllText($watchUartPath, $uart)

$fifo = Get-Content -LiteralPath $fifoPath -Raw
if ([regex]::Matches($fifo, '(?m)^module fifo\s*#').Count -ne 1) {
    throw 'Expected exactly one fifo module declaration'
}
$fifo = [regex]::Replace($fifo, '(?m)^module fifo(\s*#)', 'module fifo_tx_watch$1')
$watchFifoPath = Join-Path $build 'fifo_tx_watch.v'
[System.IO.File]::WriteAllText($watchFifoPath, $fifo)

[xml]$project = Get-Content -LiteralPath $projectPath -Raw
$project.Project.Name = 'stage2_uart_chipwatch'
$verilog = $project.SelectSingleNode('/Project/Source_Files/Verilog')
$uartNode = $verilog.SelectSingleNode('File[contains(@Path, "uart_wb_stage2.v")]')
if (!$uartNode) { throw 'UART source not found in project' }
$uartNode.SetAttribute('Path', $watchUartPath.Replace('\', '/'))
$fifoNode = $verilog.SelectSingleNode('File[contains(@Path, "/fifo.v")]')
if (!$fifoNode) { throw 'FIFO source not found in project' }
$copy = $fifoNode.CloneNode($true)
$copy.SetAttribute('Path', $watchFifoPath.Replace('\', '/'))
$copy.SelectSingleNode('FileInfo/Attr[@Name="CompileOrder"]').SetAttribute('Val', '11')
$verilog.AppendChild($copy) | Out-Null
$project.Save((Join-Path $build 'stage2_uart_chipwatch.prj'))
