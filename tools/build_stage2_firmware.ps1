param([string]$Toolchain = 'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'stage2\firmware'
$output = Join-Path $root 'stage2\build'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$cc = Join-Path $Toolchain 'riscv-none-elf-gcc.exe'
$objcopy = Join-Path $Toolchain 'riscv-none-elf-objcopy.exe'
$objdump = Join-Path $Toolchain 'riscv-none-elf-objdump.exe'
foreach ($tool in @($cc, $objcopy, $objdump)) {
    if (!(Test-Path -LiteralPath $tool)) { throw "Missing tool: $tool" }
}
$flags = @('-march=rv32im', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
    '-fno-stack-protector', '-fno-pic', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
    '-msmall-data-limit=0', '-mno-relax', '-nostdlib', '-Wall', '-Wextra', '-Werror',
    '-fstack-usage', '-Wl,--no-relax', '-Wl,--build-id=none')
Push-Location $output
try {
    foreach ($name in @('bootrom', 'app_a', 'app_b')) {
        if ($name -eq 'bootrom') {
            $inputs = @((Join-Path $source 'start.S'), (Join-Path $source 'bootrom.c'))
            $linker = Join-Path $source 'bootrom.ld'
            $defines = @()
        } else {
            $inputs = @((Join-Path $source 'app_start.S'), (Join-Path $source 'hello.c'))
            $linker = Join-Path $source 'app.ld'
            $defines = @()
            if ($name -eq 'app_b') { $defines = @('-DAPP_B=1') }
        }
        & $cc @flags @defines @inputs '-T' $linker "-Wl,-Map=$name.map" '-o' "$name.elf"
        if ($LASTEXITCODE) { throw "Failed to compile $name" }
        & $objcopy '-O' 'binary' "$name.elf" "$name.bin"
        if ($LASTEXITCODE) { throw "Failed to export $name BIN" }
        & $objdump '-d' "$name.elf" | Set-Content -LiteralPath "$name.disassembly.txt" -Encoding ascii
        if ($LASTEXITCODE) { throw "Failed to disassemble $name" }
        Write-Host "$name BIN bytes: $((Get-Item -LiteralPath "$name.bin").Length)"
    }
    & 'C:\Users\yuanj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' (Join-Path $PSScriptRoot 'bin_to_bootrom_hex.py') 'bootrom.bin' 'bootrom.hex'
    if ($LASTEXITCODE) { throw 'Failed to generate BootROM HEX' }
} finally { Pop-Location }
