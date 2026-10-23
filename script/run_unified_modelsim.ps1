param([string]$ModelSimBin = 'D:\modeltech_10.1c\win32')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/unified'
$output = Join-Path $build 'modelsim'
$library = Join-Path $output 'work'
$log = Join-Path $output 'full_crc_system.log'
$image = Join-Path $build 'freertos_xip.xip'
if (!(Test-Path $image)) { throw 'Run build_unified_firmware.ps1 first' }
foreach ($tool in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (!(Test-Path (Join-Path $ModelSimBin $tool))) {
        throw "ModelSim tool missing: $tool"
    }
}

& (Join-Path $PSScriptRoot 'run_unified_sim.ps1') -Test system -CompileOnly
New-Item -ItemType Directory -Path $output -Force | Out-Null
$sources = @('tb/stage3/tb_unified_xip.v',
             'rtl/stage3/stage3_unified_top.v',
             'build/cpu-unified/VexRiscvUnified.v',
             'rtl/stage3/stage3_flash_read.v',
             'rtl/stage3/stage3_flash_writer.v',
             'rtl/stage3/rtos_clint.v',
             'rtl/stage3/rtos_plic.v',
             'rtl/stage3/rtos_event.v',
             'rtl/common/fifo.v',
             'build/stage3/stage3_memory_sim.v',
             'build/stage3/bram_functional_models.v',
             'build/unified/uart_wb_stage2.v',
             'build/unified/uart_rx_stage2.v',
             'build/unified/uart_tx_stage2.v') | ForEach-Object { Join-Path $root $_ }

Push-Location $ModelSimBin
try {
    if (!(Test-Path $library)) {
        & .\vlib.exe $library
        if ($LASTEXITCODE) { throw 'ModelSim library creation failed' }
    }
    & .\vlog.exe -sv -work $library ('+incdir+' + (Join-Path $root 'build/flash')) @sources
    if ($LASTEXITCODE) { throw 'ModelSim unified RTL compilation failed' }

    $imageBytes = (Get-Item $image).Length
    $commands = "transcript file {$log}; cd {$build}; " +
                "vsim -novopt -lib {$library} tb_unified_xip +image_bytes=$imageBytes +PROGRESS; " +
                'run -all; quit -f'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & .\vsim.exe -c -lic_noqueue -do $commands
    $exitCode = $LASTEXITCODE
    $watch.Stop()
} finally {
    Pop-Location
}

if ($exitCode -ne 0 -or !(Test-Path $log)) {
    throw "ModelSim full-CRC simulation failed before validation; see $log"
}
$transcript = Get-Content -LiteralPath $log -Raw
$position = 0
foreach ($marker in @('BOOT FLASH', 'FREERTOS START V11.1.0',
                      'UART IRQ PASS count=1',
                      'PASS unified XIP FreeRTOS preemption, queue and interrupts')) {
    $next = $transcript.IndexOf($marker, $position, [StringComparison]::Ordinal)
    if ($next -lt 0) { throw "Missing or out-of-order ModelSim marker: $marker; see $log" }
    $position = $next + $marker.Length
}
if ($transcript -match '\*\* (Error|Fatal)|FREERTOS FAIL|Unified XIP simulation timeout') {
    throw "ModelSim reported a failure; see $log"
}
Write-Output "PASS unified full-image Flash CRC, BootROM and FreeRTOS in ModelSim ($([math]::Round($watch.Elapsed.TotalSeconds, 1)) s): $log"
