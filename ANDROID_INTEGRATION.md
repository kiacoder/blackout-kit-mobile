# Android integration

Current hardening candidate: PR #27, v1.19.4. See CURRENT_STATUS.md and docs/ENGINEERING_ACCEPTANCE.md for the current build and verification results. The November 16 milestones below are historical.

> **Latest native-build continuation — still 26%:** full development JDK/NDK recovered;
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


Existing ownership: Flutter VPNService → VpnPlugin → BlackoutVpnService → one runtime.
Xray binds a TUN fd in-process; sing-box uses a SOCKS bridge and native FD launcher.
Protect outbound sockets or bind the correct underlying network to avoid VPN recursion.
Preserve consent/revoke/foreground-service/DNS/split-app/kill-switch semantics for every
new adapter. One Android VPN owner at a time; never start competing backend services.

This change adds batch clipboard exports in the library, two parser identity fixes,
and bounded TERM/KILL cleanup of subprocess children. It does not replace an engine.
Subprocess cleanup can wait up to two grace intervals per child; move longer cleanup
away from the UI thread if adding more children. Interrupted waits force termination
and restore the interrupt flag. Test on physical ARM32/ARM64 devices before release.

Candidates: Mihomo Android socket/TUN wrapper or existing SOCKS bridge; AWG official
Android backend in an isolated service process with IPC; official WG Android tunnel
backend; OpenVPN3 JNI or a maintained Android frontend. In every case preserve raw
engine capabilities and validate exact versions. Do not expose a controller API on
all interfaces or use unprotected sockets. Reference implementations are not imported.

## Build gate
Java 17, Flutter 3.24.0 (current CI pin), Android API 34 SDK/NDK/CMake and native AARs
are needed. Consult `.github/workflows/build.yml` for artifact acquisition/build steps;
record hashes and licensing before using any newly acquired binary.
```
flutter pub get --enforce-lockfile
flutter analyze
flutter test test/
cd android && ./gradlew :app:testDebugUnitTest
# From repository root after native prerequisites:
flutter build apk --debug --target-platform android-arm64
flutter test integration_test/ -d <authorized-device>
```
At the historical November 16 checkpoint the local toolchain was incomplete. The current candidate has local and hosted test evidence in the acceptance ledger; a new physical-device run is still required. Never replace a release-signed installation with a debug-signed artifact
or claim that existing release binaries include these changes.

## Milestone 2: experimental adapter and native checks
`EngineCommands` centralizes sing-box and Mihomo CLI contracts. `NativeConfigValidator`
executes the installed checker with a deadline and discards secret-bearing diagnostics.
`EngineRunner` now uses that shared checker and an atomic temporary-file replacement.
The existing FD launcher, bridge, readiness handshake and child monitoring are reused.
Native-check failures never imply a usable connection. Lifecycle ownership races across
service startup/teardown remain a separate engineering task; this is not a completed
universal engine manager.

Mihomo is **OFF by default** via ENABLE_EXPERIMENTAL_MIHOMO. No binary is included.
On a provisioned development host, `tool/build_mihomo_android.sh` produces candidate
ARM32/64 artifacts from a fixed release commit. It has NOT completed here. Review
GPL corresponding-source/notices and native dependencies before packaging artifacts
under jniLibs; never download executables dynamically from profile URLs.
To opt in for local testing after supplying reviewed artifacts:
`ORG_GRADLE_PROJECT_enableMihomo=true flutter build apk --debug`.
This option is NOT a release approval or proof the engine works.

The subprocess must remain outside the VPN: explicitly including Blackout in an
allowed-app list is refused for Mihomo to avoid routing recursion. Custom listeners,
controllers and native TUN are disabled/rejected by runtime normalization. Fake-IP is
refused. Android DNS settings stay owned by the existing service; domain rules may
need sniffing metadata. No controller UI, health dashboard or complete engine-specific
settings UX is implemented. Keep the adapter disabled until device acceptance passes.
