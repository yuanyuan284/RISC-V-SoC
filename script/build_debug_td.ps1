param([switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/debug'
$cpu = Join-Path $root 'build/cpu-debug/VexRiscvDebug.v'
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_debug --cpu $cpu
if ($LASTEXITCODE) { throw 'Debug project preparation failed' }
if ($PrepareOnly) { return }
$verified = Join-Path $build 'stage3_debug.bit'
if (Test-Path -LiteralPath $verified) {
    # Preserve the previous result, but never leave it at the current-build path.
    Move-Item -LiteralPath $verified -Destination (Join-Path $build (
        'stage3_debug.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '_bit'))
}
$started = Get-Date
Push-Location $build
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'debug_td.tcl')
    if ($LASTEXITCODE) { throw 'Debug TD flow failed' }
    foreach ($name in @('stage3_debug.timing','stage3_debug.unverified_bit')) {
        if (!(Test-Path $name) -or (Get-Item $name).LastWriteTime -lt $started) {
            throw "Debug TD output missing or stale: $name"
        }
    }
    $timing = Get-Content 'stage3_debug.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Debug timing not closed; bitstream remains unverified'
    }
    if ($timing -notmatch 'Clock = jtag_clock, period 1000ns' -or
        $timing -notmatch 'Clock = pll/pll_inst.clkc\[1\], period 40ns') {
        throw 'Expected JTAG and CPU clock constraints missing'
    }
    Copy-Item 'stage3_debug.unverified_bit' 'stage3_debug.bit' -Force
} finally { Pop-Location }
