param(
    [string]$OutputDirectory = 'D:\risc-v\stage2_cpu_check'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sourceProject = Join-Path $root 'td_project\demo14_vexriscv_stage1_Runs\syn_1\demo14_vexriscv_stage1.prj'
$fullCpu = 'D:\fpga-3-softcores-master\vendor\vexriscv\VexRiscv.v'
if (!(Test-Path -LiteralPath $fullCpu)) { throw "Missing generated CPU: $fullCpu" }
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
if ($output.TrimEnd('\') -eq $root.TrimEnd('\')) { throw 'Use a separate output directory' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
# TD emits an unescaped ampersand in this attribute, unlike standard XML.
$text = (Get-Content -LiteralPath $sourceProject -Raw).Replace('UsedInP&R', 'UsedInP&amp;R')
[xml]$project = $text
$project.Project.Name = 'full_cpu'
$sourceBase = Split-Path $sourceProject -Parent
foreach ($node in @($project.SelectNodes('/Project/Source_Files/*/File'))) {
    $path = [System.IO.Path]::GetFullPath((Join-Path $sourceBase $node.GetAttribute('Path')))
    if ([System.IO.Path]::GetFileName($path) -eq 'VexRiscv.v') { $path = $fullCpu }
    $node.SetAttribute('Path', $path.Replace('\', '/'))
}
$watchers = $project.SelectSingleNode('/Project/Source_Files/CWC_FILE')
if ($watchers) { $watchers.ParentNode.RemoveChild($watchers) | Out-Null }
$project.Save((Join-Path $output 'full_cpu.prj'))
Push-Location $output
try {
    & 'D:\TD_5.6.5_Release_119.222\bin\td_commands_prompt.exe' (Join-Path $PSScriptRoot 'check_full_cpu.tcl')
    if ($LASTEXITCODE -ne 0) { throw 'TD candidate synthesis failed' }
} finally { Pop-Location }
Write-Host "Candidate outputs: $output"
Write-Host 'Synthesis only; no bitstream, no board programming, no functional proof.'
