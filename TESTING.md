# Testing: current verification and historical evidence

Current candidate: v1.19.4, PR #27. Local strict Dart analysis and 636 Dart tests passed at 0e1208d. Native lifecycle and vault regression evidence is recorded in [engineering acceptance](docs/ENGINEERING_ACCEPTANCE.md). Hosted checks must be verified on the final revision. No current physical-device acceptance is claimed.

## Historical checkpoint: 2026-11-16

The following sections preserve historical test results; they do not describe the current toolchain or release status.

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


## Executed here
* `.venv/bin/python -m unittest discover -s tool/tests -v`: **25 tests passed**.
* Python bytecode compilation for factory/test source: passed.
* `git diff --check`: passed at final review.
* Existing native file SHA-256/embedded Go metadata recorded, not executed version tests.
* Test output: [docs/CONFIG_FACTORY_TEST_RESULTS.txt](docs/CONFIG_FACTORY_TEST_RESULTS.txt).

Coverage includes WG/AWG identity and multi-peer preservation, header expressions,
invalid keys/addresses/ports, Hysteria version separation, JSON duplicate/ambiguity
handling, safe YAML and alias rejection, base64/JSON subscriptions, limits, dedup,
manifest separation, private permissions, symlink/overwrite refusal, failed-write
cleanup, no-secret CLI errors and CLI end-to-end packaging of synthetic fixtures.
The all-zero key in tests is a synthetic fixture, not a deployed credential.
An initial rollback test mocked every os.open call (including rmtree's directory
access); corrected to fail only file creation. Final suite is green.

## Added but NOT executed
* `test/protocol_identity_test.dart`: Hysteria v1 rejection and newer AWG detection.
* `test/profile_export_test.dart`: JSON round trip, dedup, v2rayN exclusions, empty export.
* Android `SubprocessLifecycleTest`: force-stop escalation and interrupted cleanup.
* Existing Flutter/integration/Rust/Android suites: not run; no usable toolchain/device.
* GitHub Actions workflow added for factory tests; not dispatched or observed here.

## Runtime evidence matrix
| Engine | Artifact/version evidence | Native config check | Startup/traffic/DNS | Reconnect/stop/resource/device |
|---|---|---|---|---|
| Xray | Existing AAR hashes + embedded module metadata | Not run | Not run | Not run |
| sing-box | Existing binaries hash + embedded v1.14.2 strings | Not run | Not run | Not run |
| blackout-core | Existing ARM64 binary hash + Rust source | Not run | Not run | Not run |
| Mihomo | Experimental Android adapter, binary absent | Real engine not run | Not run | Not run |
| AWG / native WG | No Android backend integration | Not run | Not run | Not run |
| OpenVPN | No Android backend integration | Not run | Not run | Not run |

Structural factory tests do not validate exact native schemas, certificates, server
settings or handshake compatibility. No new APK, server profile, live DNS test or
production verification is claimed.

## Required device/server acceptance matrix
For EACH engine + ABI + server + protocol/transport combination:
1. Record installed binary version/hash, Android OS and native API surface.
2. Validate config with that exact engine, including invalid and unsupported fields.
3. Consent/startup/foreground notification; confirm failure never reports connected.
4. TCP and UDP forwarding, IPv4/IPv6, DNS through the intended route and no leaks.
5. Wi-Fi ↔ cellular switch, airplane mode, sleep/Doze, process death and reconnect.
6. Stop/revoke/profile switch; verify no processes, sockets, TUN descriptors or routes remain.
7. Android always-on/lockdown and application kill-switch failure behavior.
8. Measure CPU/RSS/battery/start times under controlled conditions.
9. Re-test previously working profiles before deployment or signing any release.
10. Separately label implemented / compiled / engine-validated / connection-tested /
    production-verified. Record failures and rollback, never just green build badges.


## Milestone 2 executed results
* `tool/test_engine_host.sh`: **23 passed**, compiled with Kotlin 1.9.25 and run
  on Java 17. Real subprocesses and loopback sockets; native-validator unit cases
  use explicit shell test doubles, NOT a Mihomo/sing-box runtime.
* `tool/check_android_engine_sources.sh`: **passed** for eight Kotlin production
  source files against API 34 and bundled AAR classes. Uses compile-only substitutes
  for generated R/BuildConfig and MainActivity's class literal. Does NOT compile
  VpnPlugin, Flutter, resources, Gradle configuration or an APK.
* Python factory suite: **25 passed again**.
* Added Mihomo profile regression tests and export clipboard-consent widget tests;
  neither could run without Flutter/Dart. Original JUnit test runner remains unrun;
  the standalone host harness is distinct, not a claim of full regression coverage.
* `tool/build_mihomo_android.sh`: shell syntax checked, NOT executed successfully.
  An upstream host build attempt failed on blocked module downloads before compilation.

Logs: docs/ENGINE_HOST_TEST_RESULTS.txt and docs/ANDROID_API_CHECK_RESULTS.txt.
The added GitHub Actions host-check job has not been dispatched; no changes were pushed.
