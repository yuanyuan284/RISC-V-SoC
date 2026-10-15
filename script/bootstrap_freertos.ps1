. (Join-Path $PSScriptRoot 'common.ps1')
$deps = Join-Path $root 'build/deps'
New-Item -ItemType Directory -Path $deps -Force | Out-Null
$archive = Join-Path $deps 'FreeRTOS-Kernel-V11.1.0.zip'
if (!(Test-Path $archive)) {
    $request = @{Uri='https://codeload.github.com/FreeRTOS/FreeRTOS-Kernel/zip/refs/tags/V11.1.0'; OutFile=$archive}
    if ($env:HTTPS_PROXY) { $request.Proxy = $env:HTTPS_PROXY }
    Invoke-WebRequest @request
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne
    'd5875acad2479817b35b2031dc1c7c22d100f45c7f3c9f6039cb217437a298a2') {
    throw 'FreeRTOS V11.1.0 archive SHA256 mismatch'
}
if (!(Test-Path (Join-Path $deps 'FreeRTOS-Kernel-11.1.0/tasks.c'))) {
    Expand-Archive -LiteralPath $archive -DestinationPath $deps
}
Write-Host 'Official FreeRTOS-Kernel V11.1.0 ready; its MIT license stays with the dependency.'
