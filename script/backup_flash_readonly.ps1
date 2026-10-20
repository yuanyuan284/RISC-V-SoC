param([switch]$PlanOnly, [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300)
. (Join-Path $PSScriptRoot 'common.ps1')
$OpenOcd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
$bit = Join-Path $root 'build\flash\stage3_flash.bit'
$config = Join-Path $root 'script\openocd\board-iotelic-ft2232h.cfg'
if (-not (Test-Path -LiteralPath $bit -PathType Leaf)) {
    throw 'Build the Flash bitstream before attempting a hardware backup'
}
$backupDir = Join-Path $root 'build\flash\backups'
$name = 'ef2_internal_flash_{0}_{1}.bin' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N').Substring(0, 8))
$output = Join-Path $backupDir $name
$partial = "$output.partial"
$logPath = "$output.openocd.log"
$tclPath = $partial.Replace('\', '/')
$commands = "init; halt; dump_image {$tclPath} 0x30000000 0x80000; shutdown"

Write-Host 'Read-only backup of the entire 512 KiB internal Flash.'
Write-Host 'Requires the Flash bitstream already configured in FPGA SRAM.'
Write-Host "Bitstream: $bit"
Write-Host "Output: $output"
Write-Host "OpenOCD log: $logPath"
Write-Host "Read timeout: $TimeoutSeconds seconds"
if ($PlanOnly) {
    Write-Host 'Plan only: OpenOCD was not started and no file was created.'
    exit 0
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $OpenOcd
$startInfo.WorkingDirectory = $root
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in @('-f', $config, '-c', $commands)) {
    [void]$startInfo.ArgumentList.Add($argument)
}
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
    if (-not $process.Start()) { throw 'OpenOCD could not be started' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $log = ($stdout.GetAwaiter().GetResult(), $stderr.GetAwaiter().GetResult()) -join [Environment]::NewLine
    $openOcdExit = $process.ExitCode
} finally {
    $process.Dispose()
}
$log | Set-Content -LiteralPath $logPath -Encoding utf8
Write-Host $log
if ($timedOut) {
    throw "OpenOCD timed out after $TimeoutSeconds seconds; partial read is not a valid backup"
}
if ($openOcdExit -ne 0 -or
    $log -notmatch 'JTAG tap: soc\.cpu tap/device found: 0x10002fff' -or
    $log -notmatch '\[soc\.cpu\] Examination succeed' -or
    $log -match '(?m)^Error\s*:') {
    throw "OpenOCD did not complete a clean CPU JTAG read; inspect $logPath"
}
if (-not (Test-Path -LiteralPath $partial -PathType Leaf)) {
    throw 'OpenOCD did not create the backup file'
}
$size = (Get-Item -LiteralPath $partial).Length
if ($size -ne 0x80000) {
    throw "Incomplete Flash backup: $size bytes; do not treat it as a valid backup"
}
& $Python (Join-Path $PSScriptRoot 'inspect_flash_dump.py') $partial
if ($LASTEXITCODE -ne 0) { throw 'Backup analysis failed' }
Move-Item -LiteralPath $partial -Destination $output
Write-Host "Complete single-pass read: $output (compare an independent read before programming)"
