# Build and verify the isolated debug APK. Never publish this artifact.
[CmdletBinding()]
param(
    [string]$Aapt = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools\35.0.0\aapt.exe'),
    [switch]$Offline
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root '.cache\mihomo-jni\PROVENANCE.json'
if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw 'Stage and review both Mihomo candidates first.'
}
if (!(Test-Path -LiteralPath $Aapt -PathType Leaf)) {
    throw 'Provide the installed Android aapt executable.'
}
Push-Location (Join-Path $root 'android')
try {
    $gradleArgs = @(':app:assembleDebug', '-PenableMihomo=true',
        '-Ptarget-platform=android-arm,android-arm64', '--console=plain')
    if ($Offline) { $gradleArgs += '--offline' }
    & .\gradlew.bat @gradleArgs
    if ($LASTEXITCODE -ne 0) { throw 'Mihomo debug build failed.' }
} finally {
    Pop-Location
}
Push-Location $root
try {
    $apk = Join-Path $root 'build\app\outputs\apk\debug\app-debug.apk'
    & python -m tool.verify_mihomo_apk --apk $apk --manifest $manifest --aapt $Aapt
    if ($LASTEXITCODE -ne 0) { throw 'Mihomo APK verification failed.' }
    Write-Output "Verified private debug APK: $apk"
} finally {
    Pop-Location
}
