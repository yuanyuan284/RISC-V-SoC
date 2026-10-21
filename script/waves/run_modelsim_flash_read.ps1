param([string]$ModelSimBin = 'D:\modeltech_10.1c\win32')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$output = Join-Path $root 'build/waves/modelsim'
$library = Join-Path $output 'work'
$wlf = Join-Path $output 'flash_read_direct.wlf'
$log = Join-Path $output 'flash_read_direct.log'

foreach ($tool in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (!(Test-Path (Join-Path $ModelSimBin $tool))) {
        throw "ModelSim tool missing: $tool in $ModelSimBin"
    }
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

# This installation needs its own bin directory as the working directory.
Push-Location $ModelSimBin
try {
    if (!(Test-Path $library)) {
        & .\vlib.exe $library
        if ($LASTEXITCODE) { throw 'ModelSim library creation failed' }
    }
    & .\vlog.exe -sv -work $library `
        (Join-Path $root 'rtl/stage3/stage3_flash_read.v') `
        (Join-Path $root 'tb/stage3/tb_flash_read.v')
    if ($LASTEXITCODE) { throw 'ModelSim Flash RTL compilation failed' }

    $transcript = & .\vsim.exe -c -lic_noqueue -novopt -wlf $wlf `
        -lib $library tb_flash_read -do 'log -r /*; run -all; quit -f' 2>&1
    $exitCode = $LASTEXITCODE
    $transcript | Tee-Object -FilePath $log
    $transcriptText = $transcript -join "`n"
    if ($exitCode -ne 0 -or $transcriptText -notmatch
            'PASS flash read-only Wishbone SPI bridge' -or
            $transcriptText -match '\*\* (Error|Fatal)') {
        throw "ModelSim Flash RTL simulation failed; see $log"
    }
    if (!(Test-Path $wlf) -or (Get-Item $wlf).Length -eq 0) {
        throw "ModelSim direct WLF missing or empty: $wlf"
    }
    Write-Output "PASS ModelSim direct Flash RTL simulation: $wlf"
} finally {
    Pop-Location
}
