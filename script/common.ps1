$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Get-SocTool([string]$EnvironmentName, [string]$LocalDefault, [string]$Command) {
    $configured = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ($configured) { return $configured }
    if ($LocalDefault -and (Test-Path -LiteralPath $LocalDefault -PathType Leaf)) { return $LocalDefault }
    return $Command
}
$Python = Get-SocTool 'SOC_PYTHON' '' 'python'
$TdExecutable = Get-SocTool 'TD_EXECUTABLE' 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' 'td_commands_prompt.exe'
$Iverilog = Get-SocTool 'IVERILOG' 'D:\risc-v\simulator\ucrt64\bin\iverilog.exe' 'iverilog'
$Vvp = Get-SocTool 'VVP' 'D:\risc-v\simulator\ucrt64\bin\vvp.exe' 'vvp'
$VexRiscvSource = Get-SocTool 'VEXRISCV_SOURCE' 'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v' ''
$ToolchainDefault = if ($env:RISCV_TOOLCHAIN) { $env:RISCV_TOOLCHAIN } else { 'D:\risc-v\toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin' }
$simulatorDirectory = Split-Path $Iverilog -Parent
if ($simulatorDirectory -and (Test-Path -LiteralPath $simulatorDirectory -PathType Container)) {
    $env:PATH = "$(Split-Path $Iverilog -Parent);$env:PATH"
}
