param([switch]$PrepareOnly, [switch]$Jtag)
. (Join-Path $PSScriptRoot 'common.ps1')
$output = Join-Path $root 'build\stage2'
$variant = if ($Jtag) { 'stage2_jtag' } else { 'stage2_uart' }
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') $variant --cpu $VexRiscvSource
if ($LASTEXITCODE) { throw 'Stage-2 project preparation failed' }
if ($PrepareOnly) { return }
Push-Location $output
try {
    $flow = if ($Jtag) { 'stage2_jtag_td.tcl' } else { 'stage2_td.tcl' }
    & $TdExecutable (Join-Path $PSScriptRoot $flow)
    if ($LASTEXITCODE) { throw 'Stage-2 TD flow failed' }
    $timing = Get-Content -LiteralPath "$variant.timing" -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Stage-2 timing not closed; do not download the bitstream'
    }
} finally { Pop-Location }
