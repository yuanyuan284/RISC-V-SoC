. (Join-Path $PSScriptRoot 'common.ps1')
$output = Join-Path $root 'build\stage1\firmware'
New-Item -ItemType Directory -Path $output -Force | Out-Null
& $Python (Join-Path $PSScriptRoot 'make_demo_firmware.py') (Join-Path $output 'soc_fw.hex') --message 'Hello from C!'
if ($LASTEXITCODE) { throw 'Stage-1 firmware preparation failed' }
& $Python (Join-Path $PSScriptRoot 'make_demo_firmware.py') (Join-Path $output 'jtag_demo.hex')
if ($LASTEXITCODE) { throw 'Stage-1 demo preparation failed' }
