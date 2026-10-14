param([string]$OutputDirectory)
. (Join-Path $PSScriptRoot 'common.ps1')
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'build/full_cpu_check' }
& (Join-Path $PSScriptRoot 'build_td.ps1') -PrepareOnly
[xml]$project = Get-Content -LiteralPath (Join-Path $root 'build/stage1/stage1.prj') -Raw
$project.Project.Name = 'full_cpu'
foreach ($node in @($project.SelectNodes('/Project/Source_Files/Verilog/File'))) {
    if ([IO.Path]::GetFileName($node.GetAttribute('Path')) -eq 'VexRiscv.v') {
        $node.SetAttribute('Path', $VexRiscvSource.Replace('\','/'))
    }
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ($output.TrimEnd('\') -eq $root.TrimEnd('\')) { throw 'Use a separate output directory' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$project.Save((Join-Path $output 'full_cpu.prj'))
Push-Location $output
try {
    & $TdExecutable (Join-Path $PSScriptRoot 'check_full_cpu.tcl')
    if ($LASTEXITCODE) { throw 'TD candidate synthesis failed' }
} finally { Pop-Location }
Write-Host "Synthesis only; no board programming. Outputs: $output"
