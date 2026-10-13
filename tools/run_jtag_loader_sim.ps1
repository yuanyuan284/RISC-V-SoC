$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$env:PATH = "D:\risc-v\simulator\ucrt64\bin;$env:PATH"
$iverilog = 'D:\risc-v\simulator\ucrt64\bin\iverilog.exe'
$vvp = 'D:\risc-v\simulator\ucrt64\bin\vvp.exe'
$build = Join-Path $root 'stage2\build'
Push-Location $build
try {
    & $iverilog '-g2012' '-s' 'tb_jtag_loader' '-o' 'jtag_loader_test.vvp' `
        (Join-Path $root 'stage2\sim\tb_jtag_loader.v') `
        (Join-Path $root 'stage2\rtl\stage2_memory.v') `
        (Join-Path $root 'user_source\hdl_source\jtag_wb_loader.v')
    if ($LASTEXITCODE) { throw 'JTAG loader Verilog compilation failed' }
    & $vvp 'jtag_loader_test.vvp'
    if ($LASTEXITCODE) { throw 'JTAG loader simulation failed' }
} finally { Pop-Location }
