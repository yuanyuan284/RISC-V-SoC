$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build\stage2'
New-Item -ItemType Directory -Path $build -Force | Out-Null
Push-Location $build
try {
    & $iverilog '-g2012' '-s' 'tb_jtag_loader' '-o' 'jtag_loader_test.vvp' `
        (Join-Path $root 'tb\stage2\tb_jtag_loader.v') `
        (Join-Path $root 'rtl\stage2\stage2_memory.v') `
        (Join-Path $root 'rtl\common\jtag_wb_loader.v')
    if ($LASTEXITCODE) { throw 'JTAG loader Verilog compilation failed' }
    & $vvp 'jtag_loader_test.vvp'
    if ($LASTEXITCODE) { throw 'JTAG loader simulation failed' }
} finally { Pop-Location }
