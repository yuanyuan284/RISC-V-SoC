param([switch]$PrepareOnly, [switch]$Place, [switch]$Bitstream)
. (Join-Path $PSScriptRoot 'common.ps1')
if ($Place -and $Bitstream) { throw 'Choose -Place or -Bitstream, not both' }
$build = Join-Path $root 'build/unified'
$cpu = Join-Path $root 'build/cpu-unified/VexRiscvUnified.v'
if (!(Test-Path -LiteralPath $cpu)) {
    throw 'Unified CPU missing; run build_debug_cpu.ps1 -Variant unified first'
}
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_unified --cpu $cpu
if ($LASTEXITCODE) { throw 'Unified project preparation failed' }
if ($PrepareOnly) { return }
$verified = Join-Path $build 'stage3_unified.bit'
if ($Bitstream -and (Test-Path -LiteralPath $verified)) {
    Move-Item -LiteralPath $verified -Destination (Join-Path $build (
        'stage3_unified.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '_bit'))
}
Push-Location $build
try {
    $started = Get-Date
    $flow = if ($Bitstream) { 'unified_td.tcl' } elseif ($Place) {
        'unified_place.tcl'
    } else { 'unified_synth.tcl' }
    & $TdExecutable (Join-Path $PSScriptRoot $flow)
    if ($LASTEXITCODE) { throw "Unified TD $flow failed" }
    $outputs = @('stage3_unified_gate.area')
    if ($Place -or $Bitstream) {
        $outputs += @('stage3_unified_phy.area', 'stage3_unified.timing')
    }
    if ($Bitstream) { $outputs += 'stage3_unified.unverified_bit' }
    foreach ($name in $outputs) {
        if (!(Test-Path $name) -or (Get-Item $name).LastWriteTime -lt $started) {
            throw "Unified TD output missing or stale: $name"
        }
    }
    if ($Place -or $Bitstream) {
        $timing = Get-Content 'stage3_unified.timing' -Raw
        if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
            throw 'Unified TD timing is not closed'
        }
    }
    if ($Bitstream) {
        if ($timing -notmatch 'Clock = jtag_clock, period 1000ns' -or
            $timing -notmatch 'Clock = pll/pll_inst.clkc\[1\], period 40ns') {
            throw 'Expected JTAG and CPU clock constraints missing'
        }
        $bitLength = (Get-Item 'stage3_unified.unverified_bit').Length
        if ($bitLength -gt 0x50000) {
            throw "Unified bitstream ($bitLength bytes) exceeds configuration reserve"
        }
        Copy-Item 'stage3_unified.unverified_bit' 'stage3_unified.bit' -Force
    }
} finally { Pop-Location }
