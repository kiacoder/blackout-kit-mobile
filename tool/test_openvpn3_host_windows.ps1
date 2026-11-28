# Host-only OpenVPN 3 evaluation using an isolated Linux build image.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Source)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$Source = (Resolve-Path -LiteralPath $Source).Path
$pin = '4f3bdef73245d4ee9e8216c5d65baccc9568f6ef'
$revision = & git -C $Source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $revision -ne $pin) { throw 'Wrong OpenVPN source revision.' }
$status = & git -C $Source status --porcelain
if ($LASTEXITCODE -ne 0 -or $status) { throw 'Source must be clean.' }
$context = Join-Path $root '.cache\openvpn3-docker-context'
$output = Join-Path $root '.cache\openvpn3-host'
New-Item -ItemType Directory -Force $context, $output | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'openvpn3_host.Dockerfile') (Join-Path $context 'Dockerfile')
$image = 'blackout-openvpn3-host:review'
& docker build --pull=false -t $image $context
if ($LASTEXITCODE -ne 0) { throw 'OpenVPN host image build failed.' }
$common = @('run', '--rm', '--network', 'none', '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges', '-v', "${Source}:/source:ro",
    '-v', "${PSScriptRoot}:/input:ro")
$compiler = @('g++', '-std=c++17', '-O0', '-g0', '-DUSE_OPENSSL', '-DUSE_ASIO',
    '-DASIO_STANDALONE', '-DHAVE_LZ4', '-DOPENVPN_FORCE_TUN_NULL', '-I/source',
    '/input/openvpn3_profile_probe.cpp', '/source/openvpn/crypto/data_epoch.cpp',
    '-o', '/out/profile-probe', '-lssl', '-lcrypto', '-llz4', '-lxxhash', '-pthread')
& docker @common -v "${output}:/out" $image @compiler
if ($LASTEXITCODE -ne 0) { throw 'OpenVPN core compile failed.' }
& docker @common -v "${output}:/out:ro" $image bash /input/test_openvpn3_profile_probe.sh /out/profile-probe
if ($LASTEXITCODE -ne 0) { throw 'OpenVPN profile probe tests failed.' }
Get-FileHash -Algorithm SHA256 (Join-Path $output 'profile-probe')
