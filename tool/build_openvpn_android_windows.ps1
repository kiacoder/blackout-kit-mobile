# Build isolated API-24 OpenVPN JNI candidates. No app packaging or release approval.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Dependencies,
    [string]$Abi = 'arm64-v8a'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$Source = (Resolve-Path -LiteralPath $Source).Path
$Dependencies = (Resolve-Path -LiteralPath $Dependencies).Path
$mbed = Join-Path $Dependencies 'mbedtls'
$asio = Join-Path $Dependencies 'asio'
$xxhash = Join-Path $Dependencies 'xxhash'
function Assert-Source($Path, $Pin) {
    $revision = & git -C $Path rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $revision -ne $Pin) { throw 'Unexpected source revision' }
    $dirty = & git -C $Path status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Source must be clean' }
}
Assert-Source $Source '4f3bdef73245d4ee9e8216c5d65baccc9568f6ef'
Assert-Source $mbed '82e69999f91126589a28b70dd75b69fbcabe2711'
Assert-Source (Join-Path $mbed 'framework') 'ced31491c5ec907a6be533512f19dc1779230ac1'
Assert-Source $asio '190a8d8daf1cc62909b4e0c72ff491ba264ca98e'
Assert-Source $xxhash 'c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0'
$target = switch ($Abi) {
    'arm64-v8a' { 'aarch64-linux-android24' }
    'armeabi-v7a' { 'armv7a-linux-androideabi24' }
    default { throw 'Unsupported ABI' }
}
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$ndk = Join-Path $sdk 'ndk\28.2.13676358'
$cmake = Join-Path $sdk 'cmake\3.22.1\bin\cmake.exe'
$ninja = Join-Path $sdk 'cmake\3.22.1\bin\ninja.exe'
$clang = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe'
$out = Join-Path $root ".cache\openvpn3-android\$Abi"
$build = Join-Path $out 'mbedtls-build'
New-Item -ItemType Directory -Force $out | Out-Null
& $cmake -S $mbed -B $build -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake" "-DANDROID_ABI=$Abi" '-DANDROID_PLATFORM=android-24' '-DCMAKE_BUILD_TYPE=Release' '-DENABLE_PROGRAMS=OFF' '-DENABLE_TESTING=OFF' '-DUSE_SHARED_MBEDTLS_LIBRARY=OFF' '-DUSE_STATIC_MBEDTLS_LIBRARY=ON' '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'
if ($LASTEXITCODE -ne 0) { throw 'TLS configure failed' }
& $cmake --build $build --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'TLS build failed' }
$overlay = Join-Path $out 'reviewed-tls-overlay'
& python (Join-Path $PSScriptRoot 'prepare_openvpn_mbedtls_overlay.py') --source $Source --output $overlay
if ($LASTEXITCODE -ne 0) { throw 'Reviewed TLS overlay failed' }
$binary = Join-Path $out 'libopenvpn-candidate.so'
$bridge = Join-Path $root 'android\app\src\main\cpp\openvpn_jni.cpp'
$args = @("--target=$target", '-std=c++17', '-O2', '-fPIC', '-shared',
    '-fvisibility=hidden', '-DOPENVPN_CORE_API_VISIBILITY_HIDDEN', '-DUSE_MBEDTLS',
    '-DUSE_ASIO', '-DASIO_STANDALONE', '-DXXH_INLINE_ALL',
    "-I$overlay", "-I$Source", "-I$asio/asio/include", "-I$mbed/include", "-I$xxhash",
    $bridge, "$Source/openvpn/crypto/data_epoch.cpp",
    "$build/library/libmbedtls.a", "$build/library/libmbedx509.a",
    "$build/library/libmbedcrypto.a", '-static-libstdc++', '-llog',
    '-Wl,--no-undefined', '-Wl,-z,relro,-z,now,-z,noexecstack,-z,max-page-size=16384',
    '-o', $binary)
& $clang @args
if ($LASTEXITCODE -ne 0) { throw 'Android JNI compile failed' }
& python (Join-Path $PSScriptRoot 'check_android_artifact.py') --binary $binary --abi $Abi --min-sdk 24
if ($LASTEXITCODE -ne 0) { throw 'Android artifact metadata failed' }
Get-FileHash -Algorithm SHA256 $binary
