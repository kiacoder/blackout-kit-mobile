# Handoff

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


Start with [CURRENT_STATUS.md](CURRENT_STATUS.md) and [source audit](docs/EXPANSION_AUDIT.md).
All changes stay on `arena/d58a3d0b-blackout-kit-mobile`; no remote publication is needed.
No real credentials or generated deployment profiles are stored in this change.
Research clones and Python environment are ignored local scratch, not deliverables.

## Reproduce verified work
```
python3 -m venv .venv
.venv/bin/pip install -r tool/requirements-config.txt
.venv/bin/python -m unittest discover -s tool/tests -v
```
Run the Flutter parser/export tests and Android SubprocessLifecycleTest next in a
provisioned environment; they are source additions, NOT reported as passed. Then run
all existing tests/analyzer/build and physical-device lifecycle/traffic tests. Verify
new batch export menu layout, accessibility, translations, clipboard limits and
consent cancellation on narrow Android screens.

## Continue the mission
Do not switch native engines until the old baseline passes. Review actual upstream
APIs/artifact provenance/licenses before introducing dependencies. Do not copy GPL or
custom-attribution reference code into MIT source without license decisions. Official
AWG source confirms new field names but no backend integration exists here. Full
Mihomo YAML remains offline-only; do not mark it connectable in the engine hub.

Acquire server access through a secure authorized development environment, not chat
credentials. Use the SERVER_DEPLOYMENT checklist, back up before any change, and only
then generate real collections. An empty/fake v2rayN deployment file is not a deliverable.
Downloads output requires the user's actual filesystem, not this workspace.

## Milestone 2 continuation
Some tooling blockers were reduced: Java runtime/Kotlin/Go and a narrow API jar check
now work. See docs/TOOLCHAIN_PROGRESS.md for provenance and exact limitations. Run
`tool/test_engine_host.sh` and `tool/check_android_engine_sources.sh` before changing
native runners. Full Flutter/Gradle tests remain a hard next gate, including newly
added test/mihomo_profile_test.dart and test/screens/profile_export_screen_test.dart.
Mihomo is an experimental default-OFF adapter with no binary; do not change its
availability gate based on successful YAML import. Its build script pins the VPN tag,
module identity and GPL license because the default branch inspected was unrelated.
Do not import official AWG/WG backend services until VPN ownership and Go process
isolation are solved. OpenVPN3 still needs native JNI/TUN/protection integration.
