$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'stage2\build'
[xml]$project = Get-Content -LiteralPath (Join-Path $build 'stage2_uart.prj') -Raw
$project.Project.Name = 'stage2_watch_probe'
$project.Project.TOP_MODULE.MODULE = 'watch_probe_top'
$verilog = $project.SelectSingleNode('/Project/Source_Files/Verilog')
$first = $verilog.SelectSingleNode('File[1]')
foreach ($node in @($verilog.SelectNodes('File'))) {
    if ($node -ne $first) { $verilog.RemoveChild($node) | Out-Null }
}
$first.SetAttribute('Path', (Join-Path $root 'stage2\rtl\watch_probe_top.v').Replace('\', '/'))
$sdc = $project.SelectSingleNode('/Project/Source_Files/SDC_FILE/File')
$sdc.SetAttribute('Path', (Join-Path $root 'stage2\watch_probe.sdc').Replace('\', '/'))
$project.Save((Join-Path $build 'stage2_watch_probe.prj'))
