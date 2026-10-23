param([switch]$PlanOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$openocd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
$config = Join-Path $root 'script/openocd/board-iotelic-ft2232h.cfg'
$arguments = @(
    (Join-Path $PSScriptRoot 'backup_flash_segmented.py'),
    '--openocd', $openocd,
    '--config', $config,
    '--bitstream', (Join-Path $root 'build/unified/stage3_unified.bit'),
    '--output-dir', (Join-Path $root 'build/unified/backups')
)
if ($PlanOnly) {
    & $Python @arguments '--plan-only'
    if ($LASTEXITCODE) { throw 'Unified Flash backup plan failed' }
    return
}
try {
    & $Python @arguments
    if ($LASTEXITCODE) { throw 'Unified Flash backup failed; no complete backup was published' }
} finally {
    & $openocd '-f' $config '-c' 'init; resume; shutdown'
    if ($LASTEXITCODE) { throw 'Could not resume CPU after Flash backup' }
}
