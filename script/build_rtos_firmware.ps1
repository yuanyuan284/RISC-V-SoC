param([string]$Kernel)
. (Join-Path $PSScriptRoot 'common.ps1')
if (!$Kernel) { $Kernel = Join-Path $root 'build/deps/FreeRTOS-Kernel-11.1.0' }
if (!(Test-Path (Join-Path $Kernel 'tasks.c'))) { throw 'Run bootstrap_freertos.ps1 first' }
$source = Join-Path $root 'fw/rtos'
$build = Join-Path $root 'build/rtos'
$port = Join-Path $Kernel 'portable/GCC/RISC-V'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$cc = Join-Path $ToolchainDefault 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $ToolchainDefault 'riscv-none-elf-objcopy.exe'
$size = Join-Path $ToolchainDefault 'riscv-none-elf-size.exe'
$flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-Os', '-g', '-ffunction-sections',
    '-fdata-sections', '-msmall-data-limit=0', '-mno-relax', '-fno-pic',
    '-nostartfiles', '--specs=nano.specs', '--specs=nosys.specs',
    '-Wall', '-Wextra', '-Werror', '-Wl,--gc-sections', '-Wl,--no-relax', '-Wl,--build-id=none',
    '-I', $source, '-I', (Join-Path $Kernel 'include'), '-I', $port,
    '-I', (Join-Path $port 'chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions'),
    '-T', (Join-Path $source 'app.ld'))
$inputs = @((Join-Path $source 'start.S'), (Join-Path $source 'main.c'),
    (Join-Path $source 'registers.S'),
    (Join-Path $Kernel 'tasks.c'), (Join-Path $Kernel 'queue.c'), (Join-Path $Kernel 'list.c'),
    (Join-Path $Kernel 'portable/MemMang/heap_4.c'), (Join-Path $port 'port.c'),
    (Join-Path $port 'portASM.S'))
Push-Location $build
try {
    & $cc @flags @inputs '-Wl,-Map=freertos.map' '-o' 'freertos.elf'
    if ($LASTEXITCODE) { throw 'FreeRTOS compilation failed' }
    & $objcopy '-O' 'binary' 'freertos.elf' 'freertos.bin'
    if ($LASTEXITCODE) { throw 'FreeRTOS BIN export failed' }
    & $objcopy '-O' 'ihex' 'freertos.elf' 'freertos.hex'
    if ($LASTEXITCODE) { throw 'FreeRTOS Intel HEX export failed' }
    & $size 'freertos.elf'
    if ($LASTEXITCODE) { throw 'FreeRTOS size inspection failed' }
    if ((Get-Item freertos.bin).Length -gt 61440) { throw 'BIN exceeds BootROM capacity' }
} finally { Pop-Location }
