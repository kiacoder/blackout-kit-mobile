# Run only against a disposable, already booted x86-64 emulator.
# The fixture contains synthetic keys and no external traffic is forwarded.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^emulator-[0-9]+$')][string]$Serial,
    [switch]$DisposableEmulator,
    [ValidateSet("cert:tcp","encrypted-login:udp","login-only:tcp","hold:tcp")][string[]]$Cases = @("cert:tcp","encrypted-login:udp","login-only:tcp","hold:tcp")
)
$ErrorActionPreference = 'Stop'
if (!$DisposableEmulator) { throw 'Explicit disposable-emulator confirmation required.' }
$root = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$package = 'com.blackoutkit.vpn.openvpntest'
$runner = "$package.test/com.blackoutkit.vpn.OpenVpnCandidateAcceptance"
$apk = Join-Path $root '.cache/openvpn3-emulator-apks/blackout-openvpn-emulator.apk'
$test = Join-Path $root '.cache/openvpn3-emulator-apks/blackout-openvpn-emulator-instrumentation.apk'
if ((& $adb -s $Serial shell getprop ro.kernel.qemu).Trim() -ne '1' -or
    (& $adb -s $Serial shell getprop ro.product.cpu.abi).Trim() -ne 'x86_64') {
    throw 'Expected an x86-64 Android emulator.'
}
Push-Location $root
try {
    & python -m tool.stage_openvpn_candidate --emulator --apk $apk --aapt "$sdk\build-tools\35.0.0\aapt.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Wrong emulator APK.' }
    & $adb -s $Serial install -r $apk
    if ($LASTEXITCODE -ne 0) { throw 'Candidate install failed.' }
    & $adb -s $Serial install -r $test
    if ($LASTEXITCODE -ne 0) { throw 'Test APK install failed.' }
    & $adb -s $Serial shell cmd appops set $package ACTIVATE_VPN allow
    if ($LASTEXITCODE -ne 0) { throw 'Disposable emulator VPN permission failed.' }
    foreach ($case in $Cases) {
        $mode, $transport = $case.Split(':')
        $name = "blackout-emulator-lab-$PID"
        $out = Join-Path $root ('.cache\openvpn-android-fixture-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $out | Out-Null
        $started = $false
        try {
            & docker run -d --rm --name $name --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_BIND_SERVICE --device /dev/net/tun --security-opt no-new-privileges --sysctl net.ipv4.ip_forward=0 --sysctl net.ipv6.conf.all.forwarding=0 -p "127.0.0.1:11940:11940/$transport" -v "${root}:/repo:ro" -v "${out}:/fixture" blackout-openvpn-server-lab:review bash /repo/tool/test_openvpn_android_fixture.sh $mode $transport | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Fixture startup failed.' }
            $started = $true
            $profile = Join-Path $out 'profile.ovpn'
            $encoded = $null
            for ($i=0; $i -lt 60 -and !$encoded; $i++) {
                if (Test-Path $profile) {
                    try { $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) }
                    catch [IO.IOException] { }
                }
                if (!$encoded) { Start-Sleep -Milliseconds 500 }
            }
            if (!$encoded) { throw 'Fixture never became ready.' }
            $result = & $adb -s $Serial shell am instrument -w -e fixture $encoded -e mode $mode $runner
            $result
            if (($result -join "`n") -notmatch 'OPENVPN_ANDROID_TRAFFIC_PASS') {
                & docker logs $name
                throw "Android acceptance failed: $case"
            }
            Write-Output "PASS $case"
        } finally {
            if ($started) { & docker stop -t 3 $name | Out-Null }
            Remove-Item -LiteralPath $out -Recurse -Force
        }
    }
} finally {
    & $adb -s $Serial shell cmd appops set $package ACTIVATE_VPN default
    Pop-Location
}
