# Native artifact snapshot — 2026-11-16

Read-only hashes and embedded Go module strings from existing checkout.
These are NOT executed version checks, signatures, source provenance or ABI/device tests.
No binary was modified or added.

## `android/app/src/main/jniLibs/arm64-v8a/libblackout_core.so`

SHA-256: `f6d801e8f22384754d9eeda4b14cb6cd3b51c5c3a4f62371493c29f3e43046d2`

No selected Go engine module strings found (not proof of absence).

## `android/app/src/main/jniLibs/arm64-v8a/libsingbox.so`

SHA-256: `ebb9a7c7949b3e29a45ea425baefaaa897f9a4dd36da71db74b55fb18649f594`

* `mod	github.com/sagernet/sing-box	v1.14.2	h1:uZX7iz70o7lzoltR6sElMYP7kI7PVf23r4X0HQSozXM=`

## `android/app/src/main/jniLibs/arm64-v8a/libtun2socks.so`

SHA-256: `455f5e48b62c15f76cc102008ab20c0832b845235e3bcff02bd2f4660ff2266b`

No selected Go engine module strings found (not proof of absence).

## `android/app/src/main/jniLibs/armeabi-v7a/libsingbox.so`

SHA-256: `dfc42411c850e0d08ba05c43f40ec76457375fe54d97fbcaeaafdab2a9ca7b74`

* `mod	github.com/sagernet/sing-box	v1.14.2	h1:uZX7iz70o7lzoltR6sElMYP7kI7PVf23r4X0HQSozXM=`

## `android/app/src/main/jniLibs/armeabi-v7a/libtun2socks.so`

SHA-256: `59d706c60dd080e8301b9af0b9a05d78e2284429c2bb6936fdbd543e83f3285e`

No selected Go engine module strings found (not proof of absence).

## `android/app/libs/libcores.aar`

SHA-256: `6061c5f55786b0d7916f9a8721b5824fc9fe9ce44ccb67c7d8cd42f4c386bcb0`

No selected Go engine module strings found (not proof of absence).

## `android/app/libs/libcores.aar!jni/armeabi-v7a/libgojni.so`

SHA-256: `ff7ca3e6698059685852c04f8582fa3d233b1d4acd05f220e075aa2b38188e6f`

* `dep	github.com/sagernet/sing-box	v0.0.0-00010101000000-000000000000`
* `dep	github.com/xtls/xray-core	v1.260327.1-0.20261031132019-a4a3dff5b20c	h1:XijTasBJ2fImHZo1GoAgSfHuDqloQGYHEADLy9CgrJ8=`

## `android/app/libs/libcores.aar!jni/arm64-v8a/libgojni.so`

SHA-256: `4dd807a2ac500274a5f3ac10d0db57ce9a7604883a6b65079fd6415e2c70558c`

* `dep	github.com/sagernet/sing-box	v0.0.0-00010101000000-000000000000`
* `dep	github.com/xtls/xray-core	v1.260327.1-0.20261031132019-a4a3dff5b20c	h1:XijTasBJ2fImHZo1GoAgSfHuDqloQGYHEADLy9CgrJ8=`


## Build-metadata and checksum-database review (2026-11-25)

Read-only go version -m inspected both packaged ABIs of the two Go
executables and both extracted AAR JNI members without running them.
All six report GOOS=android, the expected GOARCH (arm64 or arm),
and CGO_ENABLED=1. The published sum.golang.org lookup responses
match these embedded module checksums:

| Module | Version | Module checksum | Sum database record |
| --- | --- | --- | --- |
| github.com/sagernet/sing-box | v1.14.2 | h1:uZX7iz70o7lzoltR6sElMYP7kI7PVf23r4X0HQSozXM= | 64897644 |
| github.com/xjasonlyu/tun2socks/v2 | v2.7.0 | h1:fYEN0Q1sSanuoID8xvUTsMODbKLJJH/J5ywYoMRxIPw= | 57196680 |
| github.com/xtls/xray-core | v1.260327.1-0.20261031132019-a4a3dff5b20c | h1:XijTasBJ2fImHZo1GoAgSfHuDqloQGYHEADLy9CgrJ8= | 70532272 |

A matching embedded checksum is supporting metadata, not proof that
the executable was built from those sources. The merged libgojni.so
identifies bkcores (devel), with sing-box replaced by ../sing-box
(devel). No exact embedded libbox source revision is established.
The iOS libbox script pins v1.11.4; Android standalone sing-box
is v1.14.2. Do not assume equivalent grammar across platforms.
Rebuild from independently pinned sources and verified toolchains
with device compatibility testing before replacing these artifacts.
All 12 tracked artifact hashes remain unchanged. No execution or
new native binary downloads were necessary for this audit.
