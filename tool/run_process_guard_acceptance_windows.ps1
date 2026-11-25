param(
    [switch]$RunOnDevice,
    [string]$DeviceSerial
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$Adb = Join-Path $Sdk 'platform-tools\adb.exe'
if ($RunOnDevice) {
    if (-not $DeviceSerial) { throw 'Pass -DeviceSerial for an explicitly selected ARM test device.' }
    if (-not (Test-Path $Adb -PathType Leaf)) { throw 'adb.exe is unavailable.' }
    $state = (& $Adb -s $DeviceSerial get-state | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw 'Device is not authorized.' }
    $abi = (& $Adb -s $DeviceSerial shell getprop ro.product.cpu.abi | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $abi -notin @('arm64-v8a','armeabi-v7a')) { throw 'ARM Android device required.' }
    $api = (& $Adb -s $DeviceSerial shell getprop ro.build.version.sdk | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $api -notmatch '^\d+$' -or [int]$api -lt 24) { throw 'Android API 24 or later required.' }
    $expectedCases = if ([int]$api -ge 26) { 5 } else { 4 }
}
Push-Location (Join-Path $Root 'android')
try {
    & .\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest -PenableProcessGuardExperiment=true
    if ($LASTEXITCODE -ne 0) { throw 'Acceptance APK build failed.' }
} finally { Pop-Location }
$app = Join-Path $Root 'build\app\outputs\apk\debug\app-debug.apk'
$test = Join-Path $Root 'build\app\outputs\apk\androidTest\debug\app-debug-androidTest.apk'
foreach ($apk in @($app,$test)) {
    if (-not (Test-Path $apk -PathType Leaf)) { throw "Missing APK: $apk" }
    Get-FileHash $apk -Algorithm SHA256 | Format-List
}
# Validate package identities before any install. Never replace production.
$aapt = Get-ChildItem (Join-Path $Sdk 'build-tools') -Recurse -Filter aapt.exe | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $aapt) { throw 'aapt.exe unavailable.' }
foreach ($pair in @(@($app,'com.blackoutkit.vpn.guardtest'),@($test,'com.blackoutkit.vpn.guardtest.test'))) {
    $badging = (& $aapt.FullName dump badging $pair[0] | Out-String)
    if ($LASTEXITCODE -ne 0 -or $badging -notmatch ("(?m)^package: name='" + [regex]::Escape($pair[1]) + "'")) {
        throw 'APK package identity mismatch; no install performed.'
    }
}
if (-not $RunOnDevice) {
    Write-Host 'Build and package identity verified. No device test was run.'
    return
}
foreach ($apk in @($app,$test)) {
    & $Adb -s $DeviceSerial install -r -t $apk
    if ($LASTEXITCODE -ne 0) { throw 'Isolated test APK installation failed.' }
}
$output = & $Adb -s $DeviceSerial shell am instrument -w -r com.blackoutkit.vpn.guardtest.test/com.blackoutkit.vpn.ProcessGuardAcceptance
$code = $LASTEXITCODE
$output | Write-Host
$text = $output -join "`n"
if ($code -ne 0 -or $text -notmatch ("PROCESS_GUARD_ACCEPTANCE_PASS cases=" + $expectedCases + "\b") -or $text -match 'PROCESS_GUARD_ACCEPTANCE_FAIL' -or $text -notmatch 'INSTRUMENTATION_CODE: -1') {
    throw 'Process guard device acceptance failed.'
}
Write-Host 'PASS supervisor instrumentation on the selected ARM device.'
