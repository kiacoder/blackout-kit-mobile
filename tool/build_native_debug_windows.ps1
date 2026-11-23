param(
  [switch]$SideBySide
)

$ErrorActionPreference = 'Stop'

# Build a DEBUG APK with the locally staged WG/AWG JNI libraries.
# This never enables native tunnels for release builds.
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Staging = Join-Path $Root '.cache\native-tunnel-jni'
$Expected = @(
  'arm64-v8a\libblackout-tunnels.so',
  'armeabi-v7a\libblackout-tunnels.so'
)

foreach ($Relative in $Expected) {
  $Path = Join-Path $Staging $Relative
  if (-not (Test-Path $Path -PathType Leaf)) {
    throw "Missing staged native tunnel library: $Relative. Run tool/stage_native_tunnels.py first."
  }
}

Push-Location (Join-Path $Root 'android')
try {
  $GradleArgs = @(':app:assembleDebug', '-PenableNativeTunnels=true', '--console=plain')
  if ($SideBySide) { $GradleArgs += '-PnativeTestPackage=true' }
  & .\gradlew.bat @GradleArgs
  if ($LASTEXITCODE -ne 0) { throw "Gradle debug build failed with exit code $LASTEXITCODE." }
}
finally {
  Pop-Location
}

$BuildConfig = Join-Path $Root 'build\app\generated\source\buildConfig\debug\com\blackoutkit\vpn\BuildConfig.java'
if (-not (Select-String -Path $BuildConfig -SimpleMatch 'ENABLE_EXPERIMENTAL_NATIVE_TUNNELS = true' -Quiet)) {
  throw 'Native tunnel BuildConfig flag is not true in the generated debug build.'
}

$Apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path $Apk -PathType Leaf)) { throw 'Debug APK was not produced.' }

if ($SideBySide) {
  $BuildTools = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools'
  $Aapt = Get-ChildItem $BuildTools -Recurse -File -Filter 'aapt.exe' |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($null -eq $Aapt) { throw 'aapt.exe is required to verify the side-by-side test package.' }
  $Badging = & $Aapt.FullName dump badging $Apk | Select-Object -First 1
  if ($Badging -notmatch "package: name='com\.blackoutkit\.vpn\.nativetest'") {
    throw "Unexpected side-by-side APK package: $Badging"
  }
}

$Entries = & jar tf $Apk
foreach ($Relative in $Expected) {
  $Entry = 'lib/' + ($Relative -replace '\\','/')
  if ($Entries -notcontains $Entry) {
    throw "Debug APK is missing packaged native library: $Entry"
  }
}

$Hash = (Get-FileHash -Algorithm SHA256 $Apk).Hash.ToLowerInvariant()
Write-Host "PASS native-enabled debug APK: $Apk"
Write-Host "SHA256 $Hash"
if ($SideBySide) {
  Write-Host 'Side-by-side test package requested: com.blackoutkit.vpn.nativetest'
}
Write-Host 'Release builds still force ENABLE_EXPERIMENTAL_NATIVE_TUNNELS=false.'
