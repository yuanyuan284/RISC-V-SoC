param([switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'stage3\build'
if (!(Test-Path -LiteralPath (Join-Path $output 'bootrom_init.vh'))) {
    throw 'Run build_stage3_firmware.ps1 first'
}
[xml]$project = Get-Content -LiteralPath (Join-Path $root 'stage2\build\stage2_uart.prj') -Raw
$project.Project.Name = 'stage3_uart'
$project.Project.TOP_MODULE.MODULE = 'stage3_top'
$memory = Get-Content -LiteralPath (Join-Path $root 'stage3\rtl\stage3_memory.v') -Raw
$init = Get-Content -LiteralPath (Join-Path $output 'bootrom_init.vh') -Raw
$memory = $memory.Replace('`include "bootrom_init.vh"', $init)
[System.IO.File]::WriteAllText((Join-Path $output 'stage3_memory_hw.v'), $memory)
$pll = Get-Content -LiteralPath (Join-Path $root 'stage2\build\sys_pll_stage2.v') -Raw
$pll = $pll.Replace('wire clk0_buf;', "wire clk0_buf;`n`t wire [4:0] unused_clocks;")
[System.IO.File]::WriteAllText((Join-Path $output 'sys_pll_stage3.v'), $pll)
foreach ($node in @($project.SelectNodes('/Project/Source_Files/*/File'))) {
    $path = $node.GetAttribute('Path')
    switch ([System.IO.Path]::GetFileName($path)) {
        'stage2_top.v' { $path = Join-Path $root 'stage3\rtl\stage3_top.v' }
        'stage2_memory.v' { $path = Join-Path $output 'stage3_memory_hw.v' }
        'sys_pll_stage2.v' { $path = Join-Path $output 'sys_pll_stage3.v' }
    }
    $node.SetAttribute('Path', $path.Replace('\','/'))
}
$project.Save((Join-Path $output 'stage3_uart.prj'))
if ($PrepareOnly) { return }
Push-Location $output
try {
    & 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' (Join-Path $PSScriptRoot 'stage3_td.tcl')
    if ($LASTEXITCODE) { throw 'Stage-3 TD flow failed' }
    $timing = Get-Content -LiteralPath 'stage3_uart.timing' -Raw
    if ($timing -notmatch 'Timing violations: 0 setup errors, and 0 hold errors\.') {
        throw 'Stage-3 timing not closed; do not download'
    }
} finally { Pop-Location }
