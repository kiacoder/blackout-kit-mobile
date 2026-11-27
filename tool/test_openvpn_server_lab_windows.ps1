# Host interoperability only: never attaches the host's network or routes.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Source)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$Source = (Resolve-Path -LiteralPath $Source).Path
$revision = & git -C $Source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $revision -ne '4f3bdef73245d4ee9e8216c5d65baccc9568f6ef') { throw 'Wrong OpenVPN revision.' }
$status = & git -C $Source status --porcelain
if ($LASTEXITCODE -ne 0 -or $status) { throw 'Source must be clean.' }
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
