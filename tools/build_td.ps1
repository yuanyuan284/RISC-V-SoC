param(
    [string]$TdExecutable = 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$name = 'demo14_vexriscv_stage1'
$runs = Join-Path $projectRoot "td_project\${name}_Runs"

function Invoke-TdRun([string]$RunName, [string]$OutputName) {
    $directory = Join-Path $runs $RunName
    $started = Get-Date
    Push-Location $directory
    try {
        Write-Host "Running $RunName..."
        & $TdExecutable "$name.tcl" 2>&1 | Out-File -FilePath 'build_cli.log' -Encoding utf8
        if ($LASTEXITCODE -ne 0) {
            throw "TD failed. See $directory\build_cli.log"
        }
        $output = Get-Item -LiteralPath $OutputName
        if ($output.LastWriteTime -lt $started) {
            throw "TD did not regenerate $OutputName. See $directory\build_cli.log"
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $TdExecutable -PathType Leaf)) {
    throw "TD executable not found: $TdExecutable"
}
Invoke-TdRun 'syn_1' "$name`_gate.db"
Invoke-TdRun 'phy_1' "$name.bit"

$reportPath = Join-Path $runs "phy_1\$name`_phy.timing"
$report = Get-Content -LiteralPath $reportPath -Raw
if ($report -notmatch 'Timing violations:\s*0 setup errors, and 0 hold errors\.') {
    throw "Timing has not passed. See $reportPath"
}
$summary = [regex]::Match($report, 'Minimal setup slack:[^\r\n]+').Value
$verifiedBit = Join-Path $projectRoot "td_project\$name`_verified.bit"
Copy-Item -LiteralPath (Join-Path $runs "phy_1\$name.bit") -Destination $verifiedBit
Write-Host $summary
Write-Host "Timing passed under the current constraints. Bitstream: $verifiedBit"
