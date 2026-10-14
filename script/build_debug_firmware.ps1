param([string]$Toolchain)
. (Join-Path $PSScriptRoot 'common.ps1')
if (!$Toolchain) { $Toolchain = $ToolchainDefault }
$build = Join-Path $root 'build/debug'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$cc = Join-Path $Toolchain 'riscv-none-elf-gcc.exe'
& $cc -march=rv32im -mabi=ilp32 -Og -g3 -ffreestanding -nostdlib `
    -msmall-data-limit=0 -mno-relax -Wall -Wextra -Werror `
    '-Wl,--no-relax' '-Wl,--build-id=none' -T (Join-Path $root 'fw/debug/demo.ld') `
    (Join-Path $root 'fw/common/app_start.S') (Join-Path $root 'fw/debug/demo.c') `
    -o (Join-Path $build 'debug_demo.elf')
if ($LASTEXITCODE) { throw 'Debug firmware compilation failed' }
& (Join-Path $Toolchain 'riscv-none-elf-objcopy.exe') -O binary `
    (Join-Path $build 'debug_demo.elf') (Join-Path $build 'debug_demo.bin')
if ($LASTEXITCODE) { throw 'Debug firmware BIN export failed' }
