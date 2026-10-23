param([string]$Kernel)
. (Join-Path $PSScriptRoot 'common.ps1')
if (!$Kernel) { $Kernel = Join-Path $root 'build/deps/FreeRTOS-Kernel-11.1.0' }
if (!(Test-Path (Join-Path $Kernel 'tasks.c'))) { throw 'Run bootstrap_freertos.ps1 first' }
$source = Join-Path $root 'fw/rtos'
$build = Join-Path $root 'build/unified'
$port = Join-Path $Kernel 'portable/GCC/RISC-V'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$cc = Join-Path $ToolchainDefault 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $ToolchainDefault 'riscv-none-elf-objcopy.exe'
$size = Join-Path $ToolchainDefault 'riscv-none-elf-size.exe'
$flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-Os', '-g', '-ffunction-sections',
    '-fdata-sections', '-msmall-data-limit=0', '-mno-relax', '-fno-pic',
    '-Wall', '-Wextra', '-Werror', '-I', $source,
    '-I', (Join-Path $Kernel 'include'), '-I', $port,
    '-I', (Join-Path $port 'chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions'))
$linkFlags = @('-nostartfiles', '--specs=nano.specs', '--specs=nosys.specs',
    '-Wl,--gc-sections', '-Wl,--no-relax', '-Wl,--build-id=none',
    '-T', (Join-Path $source 'app_xip.ld'))
$inputs = @((Join-Path $source 'start_xip.S'), (Join-Path $source 'main.c'),
    (Join-Path $source 'registers.S'), (Join-Path $Kernel 'queue.c'),
    (Join-Path $Kernel 'portable/MemMang/heap_4.c'), (Join-Path $port 'port.c'))
$hotSources = @(
    @((Join-Path $Kernel 'tasks.c'), 'freertos_tasks.o'),
    @((Join-Path $Kernel 'list.c'), 'freertos_list.o'),
    @((Join-Path $port 'portASM.S'), 'freertos_portASM.o'))
Push-Location $build
try {
    foreach ($item in $hotSources) {
        & $cc @flags '-c' $item[0] '-o' $item[1]
        if ($LASTEXITCODE) { throw "FreeRTOS hot code compilation failed: $($item[0])" }
    }
    $hotObjects = @($hotSources | ForEach-Object { $_[1] })
    & $cc @flags @linkFlags @inputs @hotObjects '-Wl,-Map=freertos_xip.map' '-o' 'freertos_xip.elf'
    if ($LASTEXITCODE) { throw 'FreeRTOS XIP compilation failed' }
    & $objcopy '-O' 'binary' 'freertos_xip.elf' 'freertos_xip.bin'
    if ($LASTEXITCODE) { throw 'FreeRTOS XIP BIN export failed' }
    & $size 'freertos_xip.elf'
    if ($LASTEXITCODE) { throw 'FreeRTOS XIP size inspection failed' }
    & $Python (Join-Path $PSScriptRoot 'prepare_unified_xip_image.py')
    if ($LASTEXITCODE) { throw 'FreeRTOS XIP image validation failed' }
} finally { Pop-Location }
