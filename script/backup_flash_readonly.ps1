param(
    [switch]$PlanOnly,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120,
    [ValidateRange(4096, 65536)][int]$ChunkBytes = 65536,
    [ValidateRange(2, 3)][int]$ReadPasses = 2,
    [ValidateRange(1, 3)][int]$MaxAttempts = 2
)
. (Join-Path $PSScriptRoot 'common.ps1')
$OpenOcd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
$bit = Join-Path $root 'build\flash\stage3_flash.bit'
$config = Join-Path $root 'script\openocd\board-iotelic-ft2232h.cfg'
$backupDir = Join-Path $root 'build\flash\backups'

$arguments = @(
    (Join-Path $PSScriptRoot 'backup_flash_segmented.py'),
    '--openocd', $OpenOcd,
    '--config', $config,
    '--bitstream', $bit,
    '--output-dir', $backupDir,
    '--timeout', "$TimeoutSeconds",
    '--chunk-size', "$ChunkBytes",
    '--read-passes', "$ReadPasses",
    '--max-attempts', "$MaxAttempts"
)
if ($PlanOnly) { $arguments += '--plan-only' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Segmented Flash backup failed; no complete backup was published' }
