param([string]$Toolchain = 'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if ($env:RISCV_TOOLCHAIN -and !$PSBoundParameters.ContainsKey('Toolchain')) { $Toolchain = $env:RISCV_TOOLCHAIN }
$source = Join-Path $root 'fw\stage3'
$output = Join-Path $root 'build\stage3'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$cc = Join-Path $Toolchain 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $Toolchain 'riscv-none-elf-objcopy.exe'
$size = Join-Path $Toolchain 'riscv-none-elf-size.exe'
$flags = @('-march=rv32im', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
    '-fno-stack-protector', '-fno-pic', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
    '-msmall-data-limit=0', '-mno-relax', '-nostartfiles', '-Wall', '-Wextra', '-Werror',
    '-fstack-usage', '-Wl,--no-relax', '-Wl,--build-id=none')
Push-Location $output
try {
    foreach ($name in @('bootrom','app_a','app_b')) {
        if ($name -eq 'bootrom') {
            $inputs = @((Join-Path $root 'fw\common\start.S'), (Join-Path $source 'bootrom.c'))
            $extra = @('-nostdlib', '-T', (Join-Path $source 'bootrom.ld'))
        } else {
            $inputs = @((Join-Path $root 'fw\common\app_start.S'),
                (Join-Path $source 'app.c'), (Join-Path $source 'syscalls.c'))
            $id = if ($name -eq 'app_a') { 1 } else { 2 }
            $extra = @("-DAPP_ID=$id", '--specs=nano.specs', '-u', '_printf_float',
                '-T', (Join-Path $source 'app.ld'))
        }
        & $cc @flags @inputs @extra "-Wl,-Map=$name.map" '-o' "$name.elf"
        if ($LASTEXITCODE) { throw "Failed to compile $name" }
        & $objcopy '-O' 'binary' "$name.elf" "$name.bin"
        if ($LASTEXITCODE) { throw "Failed to export $name BIN" }
        & $objcopy '-O' 'ihex' "$name.elf" "$name.hex"
        if ($LASTEXITCODE) { throw "Failed to export $name Intel HEX" }
        & $size "$name.elf"
        if ($LASTEXITCODE) { throw "Failed to inspect $name" }
    }
    & $Python (Join-Path $PSScriptRoot 'prepare_stage3_images.py')
    if ($LASTEXITCODE) { throw 'Stage-3 image preparation failed' }
} finally { Pop-Location }
