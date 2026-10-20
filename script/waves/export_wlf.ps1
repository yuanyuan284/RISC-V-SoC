param([string]$Converter = 'D:\modeltech_10.1c\win32\vcd2wlf.exe')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (!(Test-Path $Converter)) { throw "ModelSim vcd2wlf not found: $Converter" }
& python (Join-Path $PSScriptRoot 'events_to_vcd.py')
if ($LASTEXITCODE) { throw 'RTOS event VCD conversion failed' }
$sources = @(
    'build/waves/flash_read.vcd',
    'build/flash/flash_soc.vcd',
    'build/flash/flash_jtag.vcd',
    'build/stage3/debug_remote.vcd',
    'build/stage3/debug_uart.vcd',
    'build/stage3/stage3_memory.vcd',
    'build/stage3/stage3_uart.vcd',
    'build/rtos/rtos_interrupts.vcd',
    'build/waves/rtos_system_events.vcd'
)
$output = Join-Path $root 'build/waves/wlf'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Push-Location (Split-Path $Converter)
try {
    foreach ($relative in $sources) {
        $source = Join-Path $root $relative
        if (!(Test-Path $source)) { throw "Missing VCD: $source" }
        $name = [IO.Path]::GetFileNameWithoutExtension($relative)
        $target = Join-Path $output "$name.wlf"
        & $Converter $source $target
        if ($LASTEXITCODE) { throw "WLF conversion failed: $source" }
        if (!(Test-Path $target) -or (Get-Item $target).Length -eq 0) {
            throw "WLF missing or empty: $target"
        }
        Write-Output "$name -> $target"
    }
} finally {
    Pop-Location
}
