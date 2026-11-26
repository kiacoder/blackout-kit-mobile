# Current status — 2026-11-26

PR #27 hardening candidate: strict Dart analysis reports zero issues; 636 local Dart tests passed at 0e1208d, including 15 development-only authenticated vault tests. Focused native lifecycle tests, Kotlin static quality and supply-chain inventory passed at earlier checkpoints. The shipping vault still uses Hive AES-CBC; v3 experiments are not activated. Hosted verification of the final revision and physical-device acceptance remain pending. See [acceptance ledger](docs/ENGINEERING_ACCEPTANCE.md). This is not release approval.

Published stable [v1.19.3](https://github.com/kiacoder/blackout-kit-mobile/releases/tag/v1.19.3) has signed Android APKs and an unsigned iOS IPA. Main commit 81e613a carries the v1.19.4 candidate, including the PackageInstaller migration. Main tests, CodeQL, supply-chain and iOS build completed successfully; two TLS pinning alerts remain open. Physical update and network-switching acceptance is deferred, not passed. Experimental Rust, native WG/AWG and Mihomo paths are not production-proven. See [engineering acceptance](docs/ENGINEERING_ACCEPTANCE.md) and [release security](docs/RELEASE_SECURITY.md).

The following original 2026-11-16 milestones are historical, not the current release status.

# Current status — milestone 2, 2026-11-16

> **Local-only access confirmed — still 26%:** no external build/device environment
> available. Native runtime parser/routing validation hardened; 24 parser,
> 17 standalone JUnit, 13 ownership, 30 host, 33 Python checks pass and the
> Android API compile check passes. **No Flutter/Gradle/APK or Android runtime
> result.** [Current continuation](docs/NATIVE_FD_OWNERSHIP_FIX.md#local-only-continuation-after-access-clarification).

> **Native FD error-path fix — still 26%:** reproduced the old Go finalizer
> closing a recycled FD in both engines; patched constructor/bridge ownership
> together. Each engine passes 20 ownership stress tests; expanded core suites
> AWG 35 pass/2 skip and WG 30 pass/1 skip now include TUN tests. Four native
> artifacts rebuilt/staged; both Linux TUN suites pass. **No APK/device result.**
> [Cause and evidence](docs/NATIVE_FD_OWNERSHIP_FIX.md).

> **Native liveness continuation — still 26%:** secret-free device-closure JNI
> monitoring added to the gated WG/AWG service path. Four native artifacts
> rebuilt with seven exports each. 13 ownership checks, 12 standalone JUnit,
> 30 host, 15 parser and 33 Python checks pass. AWG core 26 pass/2 skip;
> WG 21 pass/1 skip; each passes ten Linux TUN checks. Gradle archive download
> blocked by redirect host; Flutter/Dart still missing. **No APK/Android runtime
> claim.** [Latest evidence](docs/NATIVE_LIVENESS_PROGRESS.md).

> **Native Android source integration — still 26%:** WG/AWG service and Flutter
> channel wiring now exists behind a default-off private debug flag. Both engines
> rebuilt with separate SONAMEs, four artifacts staged; API compile check passes.
> 10 ownership + 15 parser + 30 host + 33 Python + 7 standalone JUnit checks pass.
> AWG core 25 pass/2 skip; WG 20 pass/1 skip; each has ten Linux TUN checks passed.
> Recovered API34/build-tools mirror layout. **No Flutter build, APK or Android
> runtime verification.** [Current evidence and gates](docs/NATIVE_ANDROID_INTEGRATION.md).

> **AWG timeout update — still 26%:** deterministically reproduced stale S4
> across the first blocking TUN read; source fix now applied by native build/test
> scripts. Patched full race suite: 24 top-level passes, two skips; stress: 40/40.
> AWG and WG each pass ten Linux kernel-TUN checks. Hardened JNI compiles for
> both ARM ABIs/API24. Parser: 15 JVM checks. **Not wired into the app; no APK or
> Android device test.** [Cause, evidence and remaining gates](docs/AWG_TIMEOUT_FIX.md).

> **Earlier native-build checkpoint (superseded above) — 26%:** full development JDK/NDK recovered;
> fdlauncher and official AWG/WG JNI libraries compile for ARM64/ARM32 at API24.
> Both cores passed isolated Linux kernel-TUN TCP/DNS/restart/outage checks.
> **AWG has an unresolved intermittent race-enabled packet-test timeout.**
> Seven real JUnit tests also pass. No Flutter/Gradle build, APK or Android device test.
> [Build instructions, exact results and blockers](docs/NATIVE_BUILD_PROGRESS.md).


> **2026-11-16 continuation update (supersedes older evidence below):** overall ~26%.
> Latest preservation/security/build review: [review](docs/CONTINUATION_REVIEW.md).
> Official-release-hash-verified Mihomo Linux core: **11 integration tests passed**.
> **30 JVM host tests / 33 Python tests passed (29 factory + 4 artifact checks); eleven-file Android API check passed, including VpnPlugin against official Flutter Java declarations.**
> Android ARM64 candidate verified but API34-targeted, NOT packaged/device-tested.
> Mihomo remains disabled by default; no APK/full Flutter build or server deployment.
> See [detailed evidence and limitations](docs/MIHOMO_CORE_PROGRESS.md).


**Partial mission (~22%), not a finished multi-engine product.** No new working VPN
engine, signed APK, Android device test or server deployment is claimed.

## New implementation after milestone 1
* Shared native CLI contracts and bounded installed-engine checker; no raw diagnostic
  capture, unbounded readText or common-pool output reader.
* Experimental Mihomo Android adapter: app YAML/JSON profile → normalized document →
  platform channel → VpnService → native checker → subprocess → existing SOCKS/TUN
  bridge. Existing teardown/readiness/exit monitoring paths are reused. It is disabled
  by default and no Mihomo binary is included. This is NOT full native TUN integration.
* Full-document vault persistence and batch export via existing profile flows;
  groups/rules/HTTPS provider settings retained; per-provider cache paths isolated.
* Editor action for native sing-box/Mihomo validation, distinct from connection tests.
* Pin-checked Mihomo Android build recipe, narrow Android source compile script,
  standalone host tests and CI job (not remotely run).
* Mihomo licensing correction: the VPN release is GPL-3.0; prior MIT observation
  belonged to an unrelated default-branch tree. See the corrected audit.

## Evidence
* **25 Python tests passed again.**
* **23 Kotlin/JVM host tests passed**, including real process and loopback sockets.
* **Eight Android service/engine Kotlin files API-compiled** against API 34 and existing
  bundled core bindings. Not the Flutter plugin, Gradle/resources, or complete APK.
* Added Mihomo and export-consent Flutter tests: NOT run. Existing Flutter/JUnit/Rust
  full suites: NOT run. No real engine config, handshake, traffic or DNS test performed.

## Still missing
Working Mihomo artifact/device validation; AWG/native-WG/OpenVPN integration; complete
shared asynchronous session ownership/cancellation; runtime upgrades; full engine UI,
proxy selection, native TUN/fake-IP; all-server deployment and generated collections.

## Environment
Recovered Java JRE 17, Kotlin 1.9.25 and Go. Flutter/Dart, full JDK, SDK/NDK/build tools,
dependencies and device remain unavailable. GitHub release redirects and Go module
fetches fail under network restrictions. No server SSH agent/account/path is present.
No user Downloads mount. No push, public CI dispatch, deployment or release performed.

See TESTING.md, docs/TOOLCHAIN_PROGRESS.md and HANDOFF.md for exact continuation.
