param(
    [ValidateSet('core','gdb','download','all')][string]$Test = 'all',
    [int]$Timeout = 3600,
    [ValidateSet('jlink','cmsis-dap','iotelic-ft2232h')][string]$Adapter,
    [switch]$ConfirmRamOverwrite,
    [switch]$PlanOnly,
    [switch]$Waves
)
. (Join-Path $PSScriptRoot 'common.ps1')
$OpenOcd = Get-SocTool 'OPENOCD' 'D:\risc-v\toolchain\jtag\xpack-openocd-0.12.0-7\bin\openocd.exe' 'openocd'
$Gdb = Get-SocTool 'RISCV_GDB' (Join-Path $ToolchainDefault 'riscv-none-elf-gdb.exe') 'riscv-none-elf-gdb'
$options = @('--test', $Test, '--openocd', $OpenOcd, '--vvp', $Vvp,
    '--gdb', $Gdb, '--timeout', $Timeout)
if ($Adapter) { $options += @('--adapter', $Adapter) }
if ($ConfirmRamOverwrite) { $options += '--confirm-ram-overwrite' }
if ($PlanOnly) { $options += '--plan-only' }
if ($Waves) { $options += '--wave' }
& $Python (Join-Path $PSScriptRoot 'validate_debug_sim.py') @options
if ($LASTEXITCODE) { throw "Debug $Test validation failed; inspect build/debug logs" }
