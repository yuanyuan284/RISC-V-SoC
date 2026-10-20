param([ValidateSet('system','interrupts')][string]$Test = 'system',
      [switch]$CompileOnly, [switch]$Waves)
. (Join-Path $PSScriptRoot 'common.ps1')
$build = Join-Path $root 'build/rtos'
New-Item -ItemType Directory -Path $build -Force | Out-Null
if ($Test -eq 'interrupts') {
    Push-Location $build
    try {
        & $Iverilog '-g2012' '-s' 'tb_rtos_interrupts' '-o' 'interrupts.vvp' `
            (Join-Path $root 'tb/stage3/tb_rtos_interrupts.v') `
            (Join-Path $root 'rtl/stage3/rtos_clint.v') (Join-Path $root 'rtl/stage3/rtos_plic.v')
        if ($LASTEXITCODE) { throw 'Interrupt simulation compile failed' }
        if ($CompileOnly) { return }
        $options = @()
        if ($Waves) { $options += '+WAVE' }
        & $Vvp 'interrupts.vvp' @options | Tee-Object -FilePath 'interrupts.log'
        if ($LASTEXITCODE) { throw 'Interrupt simulation failed' }
    } finally { Pop-Location }
    return
}
$cpu = Join-Path $root 'build/cpu-rtos/VexRiscvRtos.v'
& $Python (Join-Path $PSScriptRoot 'prepare_td_project.py') stage3_rtos --cpu $cpu
if ($LASTEXITCODE) { throw 'RTOS project preparation failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_stage3_models.py')
if ($LASTEXITCODE) { throw 'BRAM models failed' }
& $Python (Join-Path $PSScriptRoot 'prepare_rtos_image.py')
if ($LASTEXITCODE) { throw 'RTOS image preparation failed' }
$sources = @((Join-Path $root 'tb/stage3/tb_rtos.v'), $cpu,
    (Join-Path $root 'rtl/stage3/stage3_rtos_top.v'),
    (Join-Path $root 'rtl/stage3/rtos_clint.v'), (Join-Path $root 'rtl/stage3/rtos_plic.v'),
    (Join-Path $root 'rtl/stage3/rtos_event.v'), (Join-Path $root 'rtl/common/fifo.v'),
    (Join-Path $root 'build/stage3/stage3_memory_sim.v'),
    (Join-Path $root 'build/stage3/bram_functional_models.v'))
$sources += @('uart_wb_stage2.v','uart_rx_stage2.v','uart_tx_stage2.v') | ForEach-Object { Join-Path $build $_ }
Push-Location $build
try {
    & $Iverilog '-g2012' '-I' (Join-Path $root 'build/stage3') '-s' 'tb_rtos' '-o' 'rtos.vvp' @sources
    if ($LASTEXITCODE) { throw 'RTOS simulation compile failed' }
    if ($CompileOnly) { return }
    $options = @()
    if ($Waves) { $options += '+WAVE' }
    & $Vvp 'rtos.vvp' @options | Tee-Object -FilePath 'simulation.log'
    if ($LASTEXITCODE) { throw 'RTOS simulation failed' }
} finally { Pop-Location }
