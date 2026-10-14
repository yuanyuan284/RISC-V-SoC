param([switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$output = Join-Path $root 'build\stage3'
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_uart --cpu $VexRiscvSource
if ($LASTEXITCODE) { throw 'Stage-3 project preparation failed' }
if ($PrepareOnly) { return }
Push-Location $output
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'stage3_td.tcl')
    if ($LASTEXITCODE) { throw 'Stage-3 TD flow failed' }
    $timing = Get-Content -LiteralPath 'stage3_uart.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Stage-3 timing not closed; do not download'
    }
} finally { Pop-Location }
