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


## Pinned standalone Go source candidates (2026-11-25)

New tool/build_pinned_go_engines.py builds isolated candidates in .cache
from pinned module and go.mod checksums, verifies module cache content,
checks embedded module/target identity and ELF API floor, and records
Go/Clang executable hashes, build metadata, source license and output
hashes. It never stages into app jniLibs. Go 1.27.0 and NDK
28.2.13676358 are required; installed toolchain hashes are recorded,
not independently authenticated. Retrieved both source archives with
matching module sums and GoModSum. Module Origin records identify
tun2socks dda1b1058db86dd0ef40d1b007de0ce86cf16a46 and sing-box
af6e64c3b69e6132ebaee0e1a3d24e93903f6709.

Tun2socks 2.7.0 built for both ABIs, API24, twice on this host with
matching SHA256 (shared compiler/module caches; NOT independent
clean-room reproduction):

- arm64-v8a: 55807d0a7bf3cff5361a4b75195cb7c2013a318394d22dd08bbde82923631283
- armeabi-v7a: 285076c8f835cba89a734941b0d82e0a82062bbdbcb460fb6d1aad1f4f2ac7b8

The historical binaries used Go 1.26.5; the candidate uses 1.27.0.
The ARM64 candidate has upstream x/crypto 0.53.0 and x/sys 0.46.0
versus historical 0.54.0 and 0.47.0. Do not promote these candidates
or assume that older dependency versions are secure. A reviewed
explicit dependency lock, independent rebuild, CLI contract/device
validation, license obligations and security review remain required.
Sing-box source pin verified; build pending. Merged AAR source
revision remains unresolved. Existing native binaries unchanged.


## Sing-box repeat builds and dependency drift (2026-11-25)

Pinned sing-box v1.14.2 candidates for both ARM ABIs pass API24 ELF
metadata validation and repeated SHA256 comparison on the same host:

- arm64-v8a: 9be733377ff046bc98e0f86e40e73946f9606b1ae83573cc915abefc055d354b
- armeabi-v7a: 101b64f664c800d1fcef4aad8fc5ba9e3fb0c8d3fd48e6c87606df7f524de1d4

Both candidate ABIs differ from the bundled dependency graph in six
modules: ajg/form, go-chi/chi/v5, go.uber.org/zap, golang.org/x/exp,
google.golang.org/genproto/googleapis/rpc, and google.golang.org/grpc.
The upstream candidate versions are older. The build tool now records
module additions/removals, version/checksum/replacement changes and
baseline binary hash; --require-matching-dependencies refuses drift.
A real tun2socks ARM64 mismatch was correctly rejected with no output
directory published. All candidates remain separate from app binaries.
Same-host repeats use shared caches, not independent reproduction.
Reviewed lock reconstruction and vulnerability assessment remain open.


## Reconstructed linked-module locks (2026-11-25)

The bundled ARM64 and ARMv7 metadata agree for each engine. New
tool/go_engine_locks/{tun2socks,singbox}.json snapshots record the
main module and 21/80 linked dependencies respectively, including
module and go.mod checksums and both bundled binary hashes. All 103
module entries were checked against Go module download metadata
with sumdb enabled. No replacement directives in these snapshots.
The --locked build mode checks the snapshots against both existing
binaries, uses pinned requirements and checksums with -mod=readonly,
verifies module content, and rejects any linked dependency drift.
It records the lock hash and preserves the generated go.mod/go.sum.

Four isolated candidate builds passed API24 ELF and exact linked
module comparison; output SHA256:

- tun2socks ARM64: a170ab634024dcd80c9adc5721e2507f37712e0fcff5da121b13c37656c01ef0
- tun2socks ARMv7: 09deff64ce7fd4c78ced30d345f21f1e61500a8b91041c70e40ab9c9b310dcac
- sing-box ARM64: 627d0942ac5c63db8f9dc1ff3620bc7827d4c82c5b91c0849fc98e889b735ba0
- sing-box ARMv7: 83649ecccb7606131b1a27cc5ddf173f5a8552ad60fc0d11850ef4d434e89c16

The lock represents linked dependencies, not the complete optional
/test module graph. A trial go mod download all received HTTP403
for google.golang.org/api v0.274.0; readonly targeted builds
succeeded without downloading that unused archive. A matching
dependency graph is not evidence of vulnerability absence, historical
binary reproduction, verified toolchain origin or Android execution.
Candidates remain in ignored .cache/*-locked-final; no bundled
artifacts replaced. Advisory review and independent clean builds
remain required before promotion.


## Linked Go advisory assessment (2026-11-25)

OSV querybatch returned 26 module/advisory matches across 92
distinct linked module versions (9 affected packages). Sing-box
25 matches, tun2socks 6, 5 shared; alias-equivalent records may
be counted separately. This is version-based screening, not
reachability analysis or standard-library assessment.

| Module | Historical version | Proposed fixed-version candidate |
| --- | --- | --- |
| github.com/andybalholm/brotli | v1.1.0 | v1.2.7 |
| github.com/go-chi/chi/v5 | v5.3.0 | v5.4.0 |
| github.com/gorilla/websocket | v1.5.3 | v1.5.4-0.20240701034025-d67f41855da4 |
| github.com/klauspost/compress | v1.19.1 | v1.20.2 |
| golang.org/x/crypto | v0.54.0 | v0.58.1-0.20261009181718-2f1f834330b2 |
| golang.org/x/mod | v0.37.0 | v0.40.0 |
| golang.org/x/net | v0.57.0 | v0.62.0 |
| golang.org/x/text | v0.40.0 | v0.41.0 |
| google.golang.org/grpc | v1.80.0 | v1.83.2 |

All nine proposed versions returned zero targeted OSV matches;
eight downloaded with sumdb enabled. compress archive HTTP403.
New audit script deduplicates module/version queries, records lock
hashes and engine attribution, rejects incomplete responses and
supports strict exit 1 for findings. CI reports findings explicitly
and uploads evidence, informational until remediation; not a release
gate. Strict live query returned exit 1. Raw advisory details are
under ignored .cache/go-lock-audit/.

Tun2socks patch trial initially introduced two x/net v0.60.0
findings via transitive selection. Explicit x/net v0.62.0 and
x/text v0.41.0 requirements resolved these in the second trial.
Both ARM ABIs built, same linked graph (23 entries including main),
API24 ELF metadata and go mod verify passed. OSV query of all 23
linked module versions returned zero matches on 2026-11-25.
Candidate dependency inputs and evidence are recorded under
tool/go_engine_candidates/tun2socks/ as snapshots, not active
Go module manifests. Candidate binaries remain ignored under
.cache/tun2socks-patched-v2. No production binary changed.
Independent rebuild, runtime compatibility, standard library and
symbol reachability analysis are pending. Sing-box patch build
remains blocked by compress archive retrieval. No release approval.


## Patched sing-box candidates and Go stdlib screening (2026-11-25)

The compress v1.20.2 proxy archive returned HTTP403 again; explicit
GOPROXY=direct retrieval from upstream succeeded with GOSUMDB enabled.
Module sum h1:v5tiZvm1KGLyg5d5oXdXe3lsSPrbEUiKoXGia//I7Qo=;
origin 7f5d8528720c895a6106f201719f87eb030a565d. All nine proposed
module upgrades were used in an isolated sing-box workspace. Both
ARM ABIs compiled, API24 ELF metadata and go mod verify passed;
identical linked module graphs across ABIs, 81 entries including
main. Fresh OSV screening returned zero linked module matches.
Candidate snapshots under tool/go_engine_candidates/singbox;
binaries only under ignored .cache/singbox-patched-trial.

Separate stdlib version screening: Go 1.26.5 (historical) 23 matches;
1.27.0 (candidate compiler) 15; 1.26.11 and 1.27.4 zero. See
STDLIB_AUDIT.json for timestamp and advisory IDs. Official go.dev
download listing returned 1.27.4 and 1.26.11 as stable. Compiler
upgrade, independently verified archive, fresh builds and repeat
module/stdlib scans still required. Zero version matches does not
prove vulnerability absence or runtime reachability. No native
binary promotion; Android device acceptance still outstanding.
