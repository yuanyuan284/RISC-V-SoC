param([switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/rtos'
$cpu = Join-Path $root 'build/cpu-rtos/VexRiscvRtos.v'
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_rtos --cpu $cpu
if ($LASTEXITCODE) { throw 'RTOS TD project preparation failed' }
if ($PrepareOnly) { return }
$verified = Join-Path $build 'stage3_rtos.bit'
if (Test-Path -LiteralPath $verified) {
    Move-Item -LiteralPath $verified -Destination (Join-Path $build (
        'stage3_rtos.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '_bit'))
}
$started = Get-Date
Push-Location $build
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'rtos_td.tcl')
    if ($LASTEXITCODE) { throw 'RTOS TD flow failed' }
    foreach ($name in @('stage3_rtos.timing','stage3_rtos.unverified_bit')) {
        if (!(Test-Path $name) -or (Get-Item $name).LastWriteTime -lt $started) {
            throw "RTOS TD output missing or stale: $name"
        }
    }
    $timing = Get-Content 'stage3_rtos.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.' -or
        $timing -notmatch 'Clock = pll/pll_inst.clkc\[1\], period 40ns') {
        throw 'RTOS timing not closed or CPU constraint missing; bitstream remains unverified'
    }
    Copy-Item 'stage3_rtos.unverified_bit' 'stage3_rtos.bit' -Force
} finally { Pop-Location }
