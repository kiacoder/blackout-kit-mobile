# Host interoperability only: never attaches the host's network or routes.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Dependencies
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$Source = (Resolve-Path -LiteralPath $Source).Path
$revision = & git -C $Source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $revision -ne '4f3bdef73245d4ee9e8216c5d65baccc9568f6ef') { throw 'Wrong OpenVPN revision.' }
$status = & git -C $Source status --porcelain
if ($LASTEXITCODE -ne 0 -or $status) { throw 'Source must be clean.' }
$Dependencies = (Resolve-Path -LiteralPath $Dependencies).Path
function Assert-PinnedSource($Path, $Pin) {
    $revision = & git -C $Path rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $revision -ne $Pin) { throw 'Wrong dependency revision.' }
    $status = & git -C $Path status --porcelain
    if ($LASTEXITCODE -ne 0 -or $status) { throw 'Dependency source must be clean.' }
}
Assert-PinnedSource (Join-Path $Dependencies 'mbedtls') '82e69999f91126589a28b70dd75b69fbcabe2711'
Assert-PinnedSource (Join-Path $Dependencies 'mbedtls/framework') 'ced31491c5ec907a6be533512f19dc1779230ac1'
Assert-PinnedSource (Join-Path $Dependencies 'asio') '190a8d8daf1cc62909b4e0c72ff491ba264ca98e'
Assert-PinnedSource (Join-Path $Dependencies 'xxhash') 'c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0'
$context = Join-Path $root '.cache\openvpn3-docker-context'
$output = Join-Path $root '.cache\openvpn3-host'
New-Item -ItemType Directory -Force $context, $output | Out-Null
$hostImage = 'blackout-openvpn3-host:review'
$labImage = 'blackout-openvpn-server-lab:review'
& docker build --pull=false -f (Join-Path $PSScriptRoot 'openvpn3_host.Dockerfile') -t $hostImage $context
if ($LASTEXITCODE -ne 0) { throw 'Host build image failed.' }
& docker build --pull=false -f (Join-Path $PSScriptRoot 'openvpn_server_lab.Dockerfile') -t $labImage $context
if ($LASTEXITCODE -ne 0) { throw 'Lab image failed.' }
& docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges -v "${Source}:/source:ro" -v "${root}:/repo:ro" -v "${output}:/out" $hostImage g++ -std=c++17 -O0 -g0 -DUSE_OPENSSL -DUSE_ASIO -DASIO_STANDALONE -DHAVE_LZ4 -DUSE_TUN_BUILDER -I/source /repo/tool/openvpn_server_lab.cpp /source/openvpn/crypto/data_epoch.cpp -o /out/server-lab -lssl -lcrypto -llz4 -lxxhash -pthread
if ($LASTEXITCODE -ne 0) { throw 'Lab client compile failed.' }
& docker run --rm --network none --cap-drop ALL --cap-add NET_ADMIN --device /dev/net/tun --security-opt no-new-privileges -v "${root}:/repo:ro" -v "${output}:/out:ro" $labImage bash /repo/tool/test_openvpn_server_lab.sh /out/server-lab
if ($LASTEXITCODE -ne 0) { throw 'Interop acceptance failed.' }

& python (Join-Path $PSScriptRoot 'prepare_openvpn_mbedtls_overlay.py') --source $Source --output (Join-Path $output 'reviewed-tls-overlay')
if ($LASTEXITCODE -ne 0) { throw 'Reviewed TLS overlay failed.' }
# Match the Android build's pinned TLS, Asio and xxHash source versions.
& docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges -v "${Dependencies}:/deps:ro" -v "${Source}:/source:ro" -v "${root}:/repo:ro" -v "${output}:/out" $labImage bash -c 'cmake -S /deps/mbedtls -B /tmp/mbed -DCMAKE_BUILD_TYPE=Release -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON && cmake --build /tmp/mbed --parallel 6 && g++ -std=c++17 -O0 -g0 -DUSE_MBEDTLS -DUSE_ASIO -DASIO_STANDALONE -DXXH_INLINE_ALL -DUSE_TUN_BUILDER -I/out/reviewed-tls-overlay -I/source -I/deps/asio/asio/include -I/deps/mbedtls/include -I/deps/xxhash /repo/tool/openvpn_server_lab.cpp /source/openvpn/crypto/data_epoch.cpp /tmp/mbed/library/libmbedtls.a /tmp/mbed/library/libmbedx509.a /tmp/mbed/library/libmbedcrypto.a -o /out/server-lab-mbed -pthread'
if ($LASTEXITCODE -ne 0) { throw 'Mbed TLS client compile failed.' }
& docker run --rm --network none --cap-drop ALL --cap-add NET_ADMIN --device /dev/net/tun --security-opt no-new-privileges -v "${root}:/repo:ro" -v "${output}:/out:ro" $labImage bash /repo/tool/test_openvpn_server_lab.sh /out/server-lab-mbed require-name
if ($LASTEXITCODE -ne 0) { throw 'Mbed TLS interop acceptance failed.' }
