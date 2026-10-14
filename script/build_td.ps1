param([switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'build_stage1_firmware.ps1')
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage1
if ($LASTEXITCODE) { throw 'Stage-1 preparation failed' }
if ($PrepareOnly) { return }
Push-Location (Join-Path $root 'build\stage1')
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'stage1_td.tcl')
    if ($LASTEXITCODE) { throw 'Stage-1 TD flow failed' }
    $timing = Get-Content -LiteralPath 'stage1.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Stage-1 timing not closed; do not download'
    }
    Copy-Item -LiteralPath stage1.bit -Destination stage1_verified.bit
} finally { Pop-Location }
