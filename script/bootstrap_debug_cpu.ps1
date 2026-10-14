. (Join-Path $PSScriptRoot 'common.ps1')
$deps = Join-Path $root 'build/deps'
New-Item -ItemType Directory -Path $deps -Force | Out-Null
$revision = 'baf7dc82f855eddaf5b0a20a6802c526f127e38a'
$archives = @(
    @{Name='vexriscv-source.zip'; Url="https://codeload.github.com/SpinalHDL/VexRiscv/zip/$revision";
      Hash='16ef143e7199d7035754bcbc870555ada38287aba8ff0e55b5a395b54b6fdec8'},
    @{Name='sbt-launch-1.6.0.jar'; Url='https://repo.maven.apache.org/maven2/org/scala-sbt/sbt-launch/1.6.0/sbt-launch-1.6.0.jar';
      Hash='627ddd9b3524369edaf891577a0c59e8bf70e783f751c12f4be779663ad29844'}
)
foreach ($archive in $archives) {
    $path = Join-Path $deps $archive.Name
    if (!(Test-Path -LiteralPath $path)) {
        $request = @{Uri=$archive.Url; OutFile=$path}
        if ($env:HTTPS_PROXY) { $request.Proxy = $env:HTTPS_PROXY }
        Invoke-WebRequest @request
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $archive.Hash) {
        throw "Dependency SHA256 mismatch: $path"
    }
}
$source = Join-Path $deps "VexRiscv-$revision"
if (!(Test-Path -LiteralPath $source)) {
    Expand-Archive -LiteralPath (Join-Path $deps 'vexriscv-source.zip') -DestinationPath $deps
}
Write-Host "Pinned debug CPU dependencies ready in $deps"
