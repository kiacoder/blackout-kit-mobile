# Disposable emulator only. The upstream fixture never connects to external hosts.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^emulator-[0-9]+$')][string]$Serial,
      [switch]$DisposableEmulator, [switch]$DirectTun)
$ErrorActionPreference = 'Stop'
if (!$DisposableEmulator) { throw 'Explicit disposable emulator confirmation required' }
$root = Split-Path -Parent $PSScriptRoot
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if ((& $adb -s $Serial shell getprop ro.kernel.qemu).Trim() -ne '1' -or
    (& $adb -s $Serial shell getprop ro.product.cpu.abi).Trim() -ne 'x86_64') {
    throw 'Expected disposable x86-64 emulator'
}
$engine = 'com.blackoutkit.vpn.mihomotest'
$probe = 'com.blackoutkit.vpn.openvpntest'
$name = "blackout-mihomo-lab-$PID"
$job = $null
$started = $false
try {
    foreach ($file in @(
        '.cache/openvpn3-emulator-apks/blackout-openvpn-emulator.apk',
        '.cache/openvpn3-emulator-apks/blackout-openvpn-emulator-instrumentation.apk',
        '.cache/mihomo-emulator-apks/mihomo-emulator.apk',
        '.cache/mihomo-emulator-apks/mihomo-emulator-instrumentation.apk')) {
        & $adb -s $Serial install -r (Join-Path $root $file)
        if ($LASTEXITCODE -ne 0) { throw "Install failed: $file" }
    }
    & $adb -s $Serial shell cmd appops set $engine ACTIVATE_VPN allow
    if ($LASTEXITCODE -ne 0) { throw 'Consent setup failed' }
    & docker run --rm -d --name $name --cap-drop ALL --security-opt no-new-privileges --sysctl net.ipv4.ip_forward=0 --sysctl net.ipv6.conf.all.forwarding=0 -p 127.0.0.1:11940:11940/tcp -p 127.0.0.1:11940:11940/udp -v "${root}:/repo:ro" blackout-openvpn-server-lab:review python3 /repo/tool/mihomo_android_socks_fixture.py | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture failed to start' }
    $started = $true
    & $adb -s $Serial shell run-as $engine rm -f files/mihomo-fixture-ready files/mihomo-fixture-stop
    if ($LASTEXITCODE -ne 0) { throw 'Could not reset fixture markers' }
    $runner = "$engine.test/com.blackoutkit.vpn.MihomoEmulatorAcceptance"
    $job = Start-Job -ScriptBlock { param($exe,$serial,$runner)
        & $exe -s $serial shell am instrument -w $runner
    } -ArgumentList $adb,$Serial,$runner
    $ready = $false
    for ($i=0; $i -lt 85; $i++) {
        if ($job.State -ne 'Running' -and $job.State -ne 'NotStarted') { break }
        $status = & $adb -s $Serial shell "run-as $engine sh -c 'test -f files/mihomo-fixture-ready && echo READY'"
        if ($status -contains 'READY') { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (!$ready) { Receive-Job $job; throw 'Engine readiness failed' }
    $mode = if ($DirectTun) { 'mihomo-direct-probe' } else { 'mihomo-probe' }
    $result = & $adb -s $Serial shell am instrument -w -e mode $mode "$probe.test/com.blackoutkit.vpn.OpenVpnCandidateAcceptance"
    $result
    if (($result -join "`n") -notmatch 'MIHOMO_ANDROID_PROBE_PASS') { & docker logs $name; throw 'Probe failed' }
    & $adb -s $Serial shell run-as $engine touch files/mihomo-fixture-stop
    if ($LASTEXITCODE -ne 0) { throw 'Stop request failed' }
    $null = Wait-Job $job -Timeout 25
    $result = Receive-Job $job
    $result
    if (($result -join "`n") -notmatch 'MIHOMO_ANDROID_SERVICE_PASS') { throw 'Service cleanup failed' }
    $logs = & docker logs $name
    $logs
    foreach ($marker in @('TCP_FIXTURE_PASS','UDP_FIXTURE_PASS','DNS_FIXTURE_PASS')) {
        if ($logs -notcontains $marker) { throw "Upstream did not observe $marker" }
    }
    Write-Output 'MIHOMO_ANDROID_ACCEPTANCE_PASS'
} finally {
    & $adb -s $Serial shell am force-stop $engine
    & $adb -s $Serial shell cmd appops set $engine ACTIVATE_VPN default
    if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force }
    if ($started) { & docker stop -t 2 $name | Out-Null }
}
