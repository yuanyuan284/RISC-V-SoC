# Keep the same pinned upstream/toolchain while generating a separate RTOS CPU.
& (Join-Path $PSScriptRoot 'build_debug_cpu.ps1') -Variant rtos
if ($LASTEXITCODE) { throw 'RTOS CPU generation failed' }
