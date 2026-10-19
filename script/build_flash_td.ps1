param([switch]$PrepareOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/flash'
$cpu = Join-Path $root 'build/cpu-debug/VexRiscvDebug.v'
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_flash --cpu $cpu
if ($LASTEXITCODE) { throw 'Flash project preparation failed' }
if ($PrepareOnly) { return }
$verified = Join-Path $build 'stage3_flash.bit'
if (Test-Path -LiteralPath $verified) {
    Move-Item -LiteralPath $verified -Destination (Join-Path $build (
        'stage3_flash.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '_bit'))
}
$started = Get-Date
Push-Location $build
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'flash_td.tcl')
    if ($LASTEXITCODE) { throw 'Flash TD flow failed' }
    foreach ($name in @('stage3_flash.timing','stage3_flash.unverified_bit')) {
        if (!(Test-Path $name) -or (Get-Item $name).LastWriteTime -lt $started) {
            throw "Flash TD output missing or stale: $name"
        }
    }
    $timing = Get-Content 'stage3_flash.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Flash timing not closed; bitstream remains unverified'
    }
    if ($timing -notmatch 'Clock = jtag_clock, period 1000ns' -or
        $timing -notmatch 'Clock = pll/pll_inst.clkc\[1\], period 40ns') {
        throw 'Expected JTAG and CPU clock constraints missing'
    }
    Copy-Item 'stage3_flash.unverified_bit' 'stage3_flash.bit' -Force
} finally { Pop-Location }
