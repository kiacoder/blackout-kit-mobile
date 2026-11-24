$ErrorActionPreference = 'Stop'

# Run the real Flutter -> MethodChannel -> WG/AWG JNI smoke on one connected ARM Android device.
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$Adb = Join-Path $Sdk 'platform-tools\adb.exe'
if (-not (Test-Path $Adb -PathType Leaf)) { throw "adb.exe not found under $Sdk" }

$Devices = & $Adb devices | Select-String '\sdevice$'
if ($Devices.Count -ne 1) {
  throw "Connect exactly one authorized Android device before running native acceptance."
}
$DeviceId = (($Devices[0].Line -split '\s+')[0]).Trim()
$Abi = (& $Adb -s $DeviceId shell getprop ro.product.cpu.abi).Trim()
if ($Abi -notmatch '^arm64-v8a$|^armeabi-v7a$') {
  throw "Native acceptance requires an ARM Android device; connected ABI is '$Abi'."
}

$Staging = Join-Path $Root '.cache\native-tunnel-jni'
foreach ($Relative in @(
  'arm64-v8a\libblackout-tunnels.so',
  'armeabi-v7a\libblackout-tunnels.so'
)) {
  if (-not (Test-Path (Join-Path $Staging $Relative) -PathType Leaf)) {
    throw "Missing staged native tunnel library: $Relative"
  }
}

Push-Location $Root
try {
  $OldGradleOpts = $env:GRADLE_OPTS
  $env:GRADLE_OPTS = '-Dorg.gradle.project.enableNativeTunnels=true'
  flutter drive -d $DeviceId --driver test_driver/integration_test.dart --target integration_test/native_tunnel_test.dart --dart-define=BLACKOUT_NATIVE_ACCEPTANCE=true
  if ($LASTEXITCODE -ne 0) { throw "Native Android acceptance failed with exit code $LASTEXITCODE." }
}
finally {
  if ($null -eq $OldGradleOpts) { Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue }
  else { $env:GRADLE_OPTS = $OldGradleOpts }
  Pop-Location
}

Write-Host "PASS native Android packaged capability and local WG/AWG lifecycle acceptance on $DeviceId ($Abi)."
