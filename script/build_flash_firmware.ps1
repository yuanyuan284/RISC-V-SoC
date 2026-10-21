param([string]$Toolchain = 'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if ($env:RISCV_TOOLCHAIN -and !$PSBoundParameters.ContainsKey('Toolchain')) {
    $Toolchain = $env:RISCV_TOOLCHAIN
}
$source = Join-Path $root 'fw/flash'
$output = Join-Path $root 'build/flash'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$cc = Join-Path $Toolchain 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $Toolchain 'riscv-none-elf-objcopy.exe'
$size = Join-Path $Toolchain 'riscv-none-elf-size.exe'
$flags = @('-march=rv32im', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
    '-fno-stack-protector', '-fno-pic', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
    '-msmall-data-limit=0', '-mno-relax', '-nostartfiles', '-nostdlib', '-Wall', '-Wextra', '-Werror',
    '-Wl,--no-relax', '-Wl,--build-id=none')
Push-Location $output
try {
    & $cc @flags (Join-Path $root 'fw/common/start.S') `
        (Join-Path $source 'bootrom.c') '-T' (Join-Path $source 'bootrom.ld') `
        '-Wl,-Map=bootrom.map' '-o' 'bootrom.elf'
    if ($LASTEXITCODE) { throw 'Flash BootROM compilation failed' }
    & $objcopy -O binary 'bootrom.elf' 'bootrom.bin'
    if ($LASTEXITCODE) { throw 'Flash BootROM export failed' }
    & $cc @flags (Join-Path $root 'fw/common/app_start.S') `
        (Join-Path $source 'hello.c') '-T' (Join-Path $source 'hello.ld') `
        '-Wl,-Map=hello.map' '-o' 'hello.elf'
    if ($LASTEXITCODE) { throw 'Flash application compilation failed' }
    & $objcopy -O binary 'hello.elf' 'hello.bin'
    if ($LASTEXITCODE) { throw 'Flash application export failed' }
    & $cc '-march=rv32im' '-mabi=ilp32' '-Os' '-ffreestanding' `
        '-Wall' '-Wextra' '-Werror' '-c' `
        (Join-Path $source 'flash_writer.c') '-o' 'flash_writer.o'
    if ($LASTEXITCODE) { throw 'RAM Flash writer driver compilation failed' }
    & $cc @flags (Join-Path $root 'fw/common/app_start.S') `
        (Join-Path $source 'ram_writer_smoke.c') `
        (Join-Path $source 'flash_writer.c') `
        '-T' (Join-Path $root 'fw/stage3/app.ld') `
        '-Wl,-Map=ram_writer_smoke.map' '-o' 'ram_writer_smoke.elf'
    if ($LASTEXITCODE) { throw 'RAM Flash writer smoke firmware compilation failed' }
    & $objcopy -O binary 'ram_writer_smoke.elf' 'ram_writer_smoke.bin'
    if ($LASTEXITCODE) { throw 'RAM Flash writer smoke BIN export failed' }
    & $size 'bootrom.elf' 'hello.elf'
    if ($LASTEXITCODE) { throw 'Flash firmware size inspection failed' }
    & $Python (Join-Path $PSScriptRoot 'prepare_flash_images.py')
    if ($LASTEXITCODE) { throw 'Flash image packaging failed' }
    & $Python (Join-Path $PSScriptRoot 'prepare_ram_writer_sim.py')
    if ($LASTEXITCODE) { throw 'RAM Flash writer simulation image preparation failed' }
} finally { Pop-Location }
