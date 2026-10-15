param(
    [string]$VexSource,
    [string]$JavaExecutable,
    [string]$SbtLauncher,
    [ValidateSet('debug','rtos')][string]$Variant = 'debug'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$revision = 'baf7dc82f855eddaf5b0a20a6802c526f127e38a'
if (!$VexSource) { $VexSource = Join-Path $root "build/deps/VexRiscv-$revision" }
if (!$JavaExecutable) {
    $JavaExecutable = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java.exe' }
    else { Get-SocTool 'SOC_JAVA' 'D:\risc-v\toolchain\jtag\jdk-17.0.20.1+1\bin\java.exe' 'java' }
}
if (!$SbtLauncher) { $SbtLauncher = Join-Path $root 'build/deps/sbt-launch-1.6.0.jar' }
if (!(Test-Path (Join-Path $VexSource 'src/main/scala/vexriscv/plugin/EmbeddedRiscvJtag.scala'))) {
    throw "Run script/bootstrap_debug_cpu.ps1 first, or supply -VexSource"
}
if (!(Test-Path $SbtLauncher)) { throw "Missing sbt launcher: $SbtLauncher" }
# The pinned upstream leaves TSELECT uninitialized; OpenOCD reads it before
# configuring hardware triggers. Give the selector an explicit reset value.
$csrPath = Join-Path $VexSource 'src/main/scala/vexriscv/plugin/CsrPlugin.scala'
$csr = [IO.File]::ReadAllText($csrPath)
$selector = 'val index = Reg(UInt(log2Up(debugTriggers) bits))'
if (!$csr.Contains($selector)) { throw 'Pinned trigger selector declaration changed' }
if (!$csr.Contains("$selector init(0)")) {
    [IO.File]::WriteAllText($csrPath, $csr.Replace($selector, "$selector init(0)"))
}
$build = Join-Path $root "build/cpu-$Variant"
$generator = if ($Variant -eq 'rtos') { 'GenRtosCpu' } else { 'GenDebugCpu' }
$definition = if ($Variant -eq 'rtos') { 'VexRiscvRtos' } else { 'VexRiscvDebug' }
$deps = Join-Path $root 'build/deps'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$generatorDir = Join-Path $VexSource 'src/main/scala/soc'
New-Item -ItemType Directory -Path $generatorDir -Force | Out-Null
Copy-Item (Join-Path $root "rtl/cpu/$generator.scala") (Join-Path $generatorDir "$generator.scala") -Force
$repositories = Join-Path $deps 'sbt-repositories'
[IO.File]::WriteAllText($repositories, "[repositories]`nlocal`nmaven-central: https://repo.maven.apache.org/maven2`n")
$options = @('-Xmx2G', '-Dsbt.supershell=false', '-Dsbt.override.build.repos=true',
    "-Dsbt.repository.config=$repositories", "-Dsbt.boot.directory=$deps/sbt-boot",
    "-Dsbt.ivy.home=$deps/ivy", "-Dcoursier.cache=$deps/coursier")
if ($env:HTTPS_PROXY) {
    $proxy = [uri]$env:HTTPS_PROXY
    $options += @("-Dhttps.proxyHost=$($proxy.Host)", "-Dhttps.proxyPort=$($proxy.Port)",
        "-Dhttp.proxyHost=$($proxy.Host)", "-Dhttp.proxyPort=$($proxy.Port)")
}
Push-Location $VexSource
try {
    & $JavaExecutable @options -jar $SbtLauncher "runMain soc.$generator $($build.Replace('\','/'))"
    if ($LASTEXITCODE) { throw "$Variant CPU generation failed" }
} finally { Pop-Location }
if (!(Test-Path (Join-Path $build "$definition.v"))) { throw "Generated $Variant CPU is missing" }
