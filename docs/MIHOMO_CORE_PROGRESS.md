# Verified Mihomo core progress — 2026-11-16

Overall mission estimate: **26%, partial**. This evidence supersedes milestone-2
statements that no real Mihomo binary has been executed; it does not change Android
engine availability. Mihomo remains disabled by default, with no binary packaged.

## Integrity recovery
Pinned VPN source: MetaCubeX/mihomo v1.19.34,
0455d0d28c4526937380505153e65a843d8612e8 (GPL-3.0).
Official release metadata was retrieved through GitHub's release API. Direct asset
retrieval failed because its redirected asset host is inaccessible. npm packages
`@pkgship/mihomo-linux-amd64@1.19.34` and
`@pkgship/mihomo-android-arm64@1.19.34` were unpacked without running install scripts.
They are third-party transport, NOT independently trusted upstream signatures.

Before execution, GNU gzip level 6 with the original basename and upstream mtime
reconstructed archives matching the **complete official release SHA-256** exactly.
The original mtime was recovered within the upstream Build core job interval;
no payload bytes were modified. Verification is reproducible with
`tool/verify_mihomo_release.py`. The trust anchor is the GitHub official release
metadata, not npm metadata or self-reported binary version. This is not a signed
reproducible-source-build attestation.

* Linux asset 734505033: `mihomo-linux-amd64-v1.19.34.gz`;
  archive SHA-256 `223fab877e5795ce780ba39902e5f0b1113c1256ae244a7160f1165e017e9ccc`.
* Android asset 734505069: `mihomo-android-arm64-v8-v1.19.34.gz`;
  archive SHA-256 `48a71fc6a68e2909587176e0ab7185d8f2fac298fa96ccdacf30ea86ab2359b5`.
* See MIHOMO_LINUX_INTEGRITY_RESULTS.txt and MIHOMO_ANDROID_INTEGRITY_RESULTS.txt
  for unpacked binary hashes. Binaries remain ignored local cache, not distributed.

Linux reports v1.19.34, Go 1.26.11, with_gvisor, amd64 v3. Android metadata is
AArch64 PIE, CGO enabled, Android ident **API 34**, NDK r29-beta1. This candidate
must NOT be treated as compatible with this app's minSdk24. Build from source
against the supported API floor and test devices before packaging. GPL source,
notices, corresponding-source delivery and app-combination obligations remain a
release gate; integrity verification is not licensing clearance.

## Real tests
`tool/test_mihomo_core.py` requires an explicit binary and expected SHA-256.
11 tests passed with disposable loopback HTTP/DNS/UDP fixtures, no server profiles:
version/native validation, invalid config, TCP by IP/name, DNS upstream, reject
routing, DIRECT/REJECT group switching, controller authentication, UDP forwarding,
three restart/shutdown cycles, and upstream outage/recovery without core restart.
The first UDP run timed out; isolated debug execution passed. The test now handles
UDP loss/startup readiness with bounded retransmission (six attempts), not an
unbounded wait. TCP readiness alone does not prove UDP readiness.

Results: MIHOMO_CORE_TEST_RESULTS.txt and MIHOMO_CORE_RESULTS.json. Recorded RSS
and startup observations are Linux fixture measurements, NOT mobile benchmarks.
No encrypted remote outbound, Android TUN, tun2socks bridge, protect(), real network
handover, reboot, battery behavior or deployed-server connectivity was tested.

Reproduce after obtaining the exact candidate:
```
python3 tool/verify_mihomo_release.py --platform linux-amd64 --binary PATH
python3 tool/test_mihomo_core.py --binary PATH \
  --sha256 0a68807c7c93963bb66d07717fe0f3ac3945b422b525f8a1e19438d278d7ae11
```

## Source build / environment
131 dependency archives plus 3 cached were checksum verified against upstream
module sums. Source-build attempt still fails on exact GitLab bsaes and aes-ccm
sources. A GitHub bsaes mirror checksum did NOT match and was rejected. No module
hash verification was disabled, and no successful local source build is claimed.
Private runner listing returned 403; inspected historical job was GitHub-hosted,
not an authorized private host. No credentials/access route was discovered and no
remote jobs, push, fork, PR, tag or release were initiated.

Needed private environment: Flutter/Dart compatible with project lockfile; maintained
Java17 JDK, Android SDK API34/build-tools and supported NDK; Gradle dependencies;
Go/Rust, CMake/Ninja; permitted upstream/module/artifact access; emulator and physical
API24+ device coverage. Signing material and VPN secrets must stay outside chat/logs.

## Lifecycle / repository handoff
26 JVM host tests passed, including cancellation serialization, cleanup-failure
startup refusal and close rejection. Nine production service/engine Kotlin files
API-compile; VpnPlugin, Flutter/AGP/resources and complete APK are not covered.
Global plugin callback ownership and service lifecycle still require further review
and Android tests before claiming reliable integration.
25 Python configuration regressions passed again.

Actual Git history in this resumed workspace shows base 9c4213d only, despite older
session memory mentioning later commits. Implementation files are present as local
modified/untracked files. They have been preserved, not reset or overwritten by
historical versions. No publication or speculative history reconstruction was done.
