param(
    [string]$Port = 'COM3',
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 300,
    [string]$ExpectedAppLine = 'HELLO,YUAN!',
    [switch]$PlanOnly
)

. (Join-Path $PSScriptRoot 'common.ps1')
$outputDir = Join-Path $root 'build/flash'
$logPath = Join-Path $outputDir ('poweron_uart_{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host "Port: $Port, 115200 8N1"
Write-Host "Timeout: $TimeoutSeconds seconds"
Write-Host "Expected application line: $ExpectedAppLine"
Write-Host "Log: $logPath"
Write-Host 'This listener does not configure the FPGA or write Flash.'
if ($PlanOnly) {
    Write-Host 'Plan only: serial port was not opened.'
    return
}

Add-Type -AssemblyName System.IO.Ports
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$output = [System.Text.StringBuilder]::new()
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    Write-Host 'LISTEN_READY: now power-cycle only the EF2 board.'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $serial.ReadExisting()
        if ($chunk) {
            [void]$output.Append($chunk)
            [Console]::Write($chunk)
            $text = $output.ToString()
            if ($text.Contains("BOOT FLASH`r`n") -and
                $text.Contains("$ExpectedAppLine`r`n")) {
                break
            }
        }
        Start-Sleep -Milliseconds 50
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$text = $output.ToString()
[System.IO.File]::WriteAllText($logPath, $text, [System.Text.Encoding]::UTF8)
if (-not ($text.Contains("BOOT FLASH`r`n") -and
          $text.Contains("$ExpectedAppLine`r`n"))) {
    throw "Startup UART markers not observed before timeout; inspect $logPath"
}
Write-Host "UART_BANNERS_OBSERVED: $logPath"
Write-Host 'Confirm separately that board power was removed and no FPGA JTAG download occurred.'
