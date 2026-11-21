# Native build and real kernel-TUN progress

> **Latest source integration:** [NATIVE_ANDROID_INTEGRATION.md](NATIVE_ANDROID_INTEGRATION.md).
> WG/AWG now have gated service/channel wiring, freshly rebuilt distinct debug
> libraries, and a verified opt-in debug APK packaging path. Android runtime and
> physical-device acceptance gates remain unmet.

> **Superseding AWG timeout evidence:** see [AWG_TIMEOUT_FIX.md](AWG_TIMEOUT_FIX.md).
> The initial-read defect is reproduced and patched in the build/test path;
> Android service integration and device verification remain outstanding.

**Current checkpoint: native-enabled DEBUG APK packaging is proven; no
physical-device VPN execution, server deployment, release publication, or
production-readiness claim is made.**

The accepted 66-file inventory is preserved byte-for-byte:
`docs/CHANGE_REVIEW_INVENTORY.json` SHA-256
`d50b371b134d61a1c2cbd1c04ca82e7b5cfe673d8204129d6a6f73e75bbda42a`.
New evidence is separate. Ignored tool caches had disappeared on continuation;
the recovery scripts below make this work recoverable without committing binaries.

## A. Build environment: actual progress and remaining blockers
Recovered and executed:
* Full JDK **17.0.2**, including javac, from Microsoft's AOSP mirror
  `msft-mirror-aosp/platform.prebuilts.jdk.jdk17`, revision
  `c253484c29dfee6f91cc1f616b5cce87a299d511`, branch android13-d1-release.
* Android NDK **r22 / 22.0.7026061**, from Deno's mirror `denoland/android_ndk`,
  revision `401019bf85744311b26c88ced255cd53401af8b7`.
* CMake 3.22.6, Ninja 1.13.2, Go 1.26.6 via pinned PyPI distributions;
  Kotlin 1.9.25 via the previously hash-verified npm archive.

These OLD JDK/NDK mirrors are development tools, not release-toolchain approval.
Git revision pinning establishes the mirror tree used, not an independently
verified original Google distribution signature. Prefer maintained official tools
on the private release machine. No signing credentials are used.

The app's **real fdlauncher C code compiled and linked for ARM64 and ARM32, API24**
using its CMake project. Initial configuration failed because sparse checkout omitted
NDK build/cmake; recovering that directory fixed it. The source was not replaced by
stubs. Build logs: FDLAUNCHER_ARM64_BUILD.txt and FDLAUNCHER_ARM32_BUILD.txt.

Full JDK enabled compilation of official JUnit source, tag r4.13.2/revision
`05fe2a64f59127c02135be22f416e91260d6ede6`, with its bundled Hamcrest.
**All seven current Kotlin JUnit tests passed.** The official source's version
string says 4.13.2-SNAPSHOT; this is a source build at that release tag, not a claimed
Maven binary. This run is real JUnit but **not Gradle test execution**.

A later Windows-host continuation recovered the missing app-build side: Flutter
3.24/Dart, Java 17, Android API34/build-tools, platform-tools and Gradle dependency
resolution are now usable. The full Flutter suite passes 545/545, CI-style analyze
exits 0, the Blackout app-module Android unit tests pass, and both normal and
native-enabled debug APKs build. No Android emulator or physical Android device is
connected, so runtime VPN/JNI acceptance is still blocked. No minSdk increase was made.

## B. Mihomo
No compatible Mihomo Android artifact was obtained. The already verified upstream
ARM64 candidate remains API34-targeted and rejected for this minSdk24 app.
Official build workflows inspected at v1.19.12, v1.19.0 and v1.18.10 also select
`aarch64-linux-android34`; no verified API24 alternative was found in that search.
The npm transport offers 1.19.30–1.19.34, not a proven minSdk24 alternative.

A compatible NDK compiler is now available, removing one source-build blocker.
Exact v1.19.34 GitLab bsaes/aes-ccm source dependencies remain unresolved through
permitted hosts. Additional GitHub mirror searches did not resolve them. No checksum
bypass, crypto substitution, dependency removal, or undocumented downgrade was used.
Mihomo remains OFF. Its prior 11 Linux integration tests are historical evidence,
not newly executed Android traffic tests.

## C. Official AWG and WireGuard: real native builds
Pinned official Android sources:
* AmneziaWG: `ff15093bf3856fea0947923474870b86efb682f0`, using
  amneziawg-go/v3 v3.1.20260814.
* WireGuard: `e7b3a3c118836e112620b1302a8ba1873ad4daac`, using
  wireguard v0.0.0-20250521234502-f333402bd9cb.

Recovered **9/9 AWG** and **8/8 WG** module archives. Go's own x/mod module ZIP
implementation verifies both module ZIP and go.mod h1 against pinned go.sum before
publishing to a local proxy. The later staging gate also parses each ELF dynamic
symbol table directly and requires all seven JNI exports for the selected engine;
`JNI_SYMBOLS.txt` is no longer trusted as staging evidence. The wintun source mapping initially failed; an exact
commit mirror in nbdy/wintun-go matched upstream checksums. It was not replaced by
a different Windows implementation. No sum verification was disabled.

Both official JNI backends compile for **arm64-v8a and armeabi-v7a at API24**.
The builds use Go1.26.6 with the official CLOCK_BOOTTIME patch applied to a separate
Go toolchain copy. This resolves the AWG Makefile's Go1.24.2 versus go.mod1.25
mismatch for these development builds; it is not a claim that upstream's stock
Makefile succeeds unchanged. Patch SHA-256:
`149ab7d9a1c20dad61fe279a837e0e0c81c6b2f5584614ac4d4cde67008755f0`.
The same patch is present in both pinned Android sources.

The reproducible script sets the correct module-specific IPC socketDirectory under
this app's private cache (AWG requires the `/v3` import path), checks all six expected
JNI exports, and runs the ELF ABI/API gate for both ABIs. Artifacts remain in ignored
cache only. Both upstream backends use the same `libwg-go.so` SONAME: **do not
co-package them under that name**. Distinct library loading/naming must be designed
and tested before app integration. ET_DYN metadata denotes a shared library or PIE,
not proof of executable or device compatibility. The gate wording now reflects that.

Build evidence: AWG_ANDROID_BUILD.txt, WIREGUARD_ANDROID_BUILD.txt,
AWG_DEPENDENCY_RESULTS.txt, WIREGUARD_DEPENDENCY_RESULTS.txt and
NATIVE_COMPILE_RESULTS.json. No native app library was replaced.

## D. Tests: successes AND an unresolved failure
Pinned Linux host core suites:
* AWG device/conn/replay: **21 top-level pass, 2 skip**; 49 pass including subtests.
* WG device/conn/replay: **20 top-level pass, 1 skip**; 46 pass including subtests.
* Initial AWG selected race suite: **4 top-level pass, 1 skip**.
* Repeated AWG race suite: **FAILED** on TestAWGDevicePing/ping_1.0.0.2, return packet
  timeout. Focused five-run reproduction: **4 pass, 1 fail**. No data-race warning
  was identified; this is an intermittent forwarding-test timeout with unresolved
  cause, not proof of a particular core defect. The aggregate test script correctly
  stops on failure. No retry was inserted into that upstream test to hide it.
* Two added AWG tests pass with race detection: finite I1–I5 advanced packet patterns
  plus S1–S4/header ranges, and native invalid-setting rejection while preserving
  the previous session. The first fixture copied `<c>` from a skipped upstream
  manual example; the actual parser rejects it. That run failed then timed out.
  The corrected fixture uses supported tags, tests rejection of `<c>`, and aborts
  on helper setup failure before trying to send. The module cache is not edited;
  added tests use an overlay on a disposable verified source copy.

The upstream skipped tests are not passed tests. In particular the manual
TestAWGHandshakeDevicePing is skipped, and TestWaitPool is disabled.
Detailed attempt counts, failures and skipped names: NATIVE_CORE_TEST_RESULTS.json.
Raw upstream debug logs stay in private ignored .buildlog; reports omit key material.

### Real Linux kernel-TUN forwarding
Passwordless local sudo and isolated network namespaces were available. A bounded
fixture creates TWO network namespaces, a private veth link, and two real kernel
TUNs. It never changes the host network namespace or contacts external servers.
Fresh X25519 keys are generated in memory; temporary 0600 configs are removed.

**Both AWG and WG passed 10 checks each**: TCP fixture traffic, UDP DNS fixture
traffic and TUN removal over three startup/shutdown cycles, plus outer-link outage
blocking/recovery. Bidirectional kernel TUN counters are recorded. AWG uses junk,
S1–S4, H1–H4 ranges and I1–I5 patterns; WG uses its independent standard core.
This is not merely a SOCKS handshake or in-memory TUN demo. However it does NOT test
Android JNI, VpnService, protect(), Binder FD transfer, Wi-Fi/mobile handover,
Android DNS integration, or a physical device. TCP readiness/recovery is bounded
and may retry; the upstream single-packet timeout remains a blocker despite these
kernel tests passing. See AWG_KERNEL_TUN_RESULTS.json and WIREGUARD_KERNEL_TUN_RESULTS.json.

Existing application regressions rerun: **30 host tests, 33 Python tests, 7 JUnit
tests passed**, plus the eleven-file API check after the logging changes. No full
Flutter or Gradle suite is reported as passed. Xray/sing-box binaries and profile
vault/factory remain unchanged by this continuation's native experiments.

## E. Security / release gates before Android integration
* EngineRunner now discards subprocess and tun2socks output instead of appending raw
  engine.log. The sing-box probe shares NativeConfigValidator and discards output;
  its old unbounded raw checker capture and error log-tail disclosure are removed.
  Existing historical log files were not deleted. Other wrappers and library-native
  logcat paths still need review; full log redaction is NOT complete.
* Both official AWG/WG JNI bridges emit native debug/error logs. Their IpcSet failure
  path closes the raw FD after creating a Device rather than clearly closing the
  Device; later failure branches call uapiFile.Close without an explicit nil guard
  after UAPIOpen failure. These are source-review concerns requiring fixes/tests
  before adoption, not device-reproduced failures.
* Keep a single Android VPNService owner. Official backend services cannot simply
  be added alongside BlackoutVpnService. Descriptor ownership, socket protection,
  lifecycle serialization and reattachment still need actual integration.
* Android binding source is Apache-2.0; Go AWG/WG cores carry MIT licenses. Preserve
  notices and verify all linked dependencies, Go runtime and patches. These findings
  do not clear native distribution. Mihomo GPL corresponding-source/app-combination
  obligations remain separate. No license is overwritten by the root MIT license.

## Reproduction (private Linux host; no uploads)
```
bash tool/recover_native_toolchain.sh
export JAVA_HOME="$PWD/.cache/toolchains/aosp-jdk17/linux-x86"
export ANDROID_NDK_HOME="$PWD/.cache/toolchains/android-ndk-r22"
export KOTLINC="$PWD/.cache/toolchains/package/bin/kotlinc"
export PATH="$JAVA_HOME/bin:$PWD/.venv/bin:$PATH"
bash tool/test_kotlin_junit_local.sh
bash tool/test_engine_host.sh
.venv/bin/python -m unittest discover -s tool/tests -v
```
Clone the official Android sources at the revisions above into .cache/references,
then recover modules (the script validates source revision and go.sum):
```
.venv/bin/python tool/recover_awg_modules.py --engine awg \
  --source .cache/references/amneziawg-android --go "$PWD/.venv/bin/go"
.venv/bin/python tool/recover_awg_modules.py --engine wireguard \
  --source .cache/references/wireguard-android --go "$PWD/.venv/bin/go"
# Use a NEW directory; never patch the original Go installation.
cp -a "$(.venv/bin/go env GOROOT)" .cache/toolchains/go-backend-patched
patch -p1 -d .cache/toolchains/go-backend-patched < \
  .cache/references/amneziawg-android/tunnel/tools/libwg-go/goruntime-boottime-over-monotonic.diff
export GO_BACKEND_ROOT="$PWD/.cache/toolchains/go-backend-patched"
bash tool/build_android_go_backend.sh awg .cache/references/amneziawg-android .cache/awg-new-build
bash tool/build_android_go_backend.sh wireguard .cache/references/wireguard-android .cache/wg-new-build
bash tool/test_native_go_backends.sh wireguard .cache/references/wireguard-android --kernel
bash tool/test_native_go_backends.sh awg .cache/references/amneziawg-android --kernel
```
AWG's aggregate script may stop at the documented intermittent race failure. This
must remain visible. Kernel fixtures require passwordless sudo, ip, nsenter and
unshare; do not run them on a production host.

For native DEBUG packaging after staging the four libraries, use the explicit
Gradle property rather than relying on Flutter to forward an environment property:
```
cd android
./gradlew :app:assembleDebug -PenableNativeTunnels=true
```
On Windows, `tool/build_native_debug_windows.ps1` additionally verifies the debug
BuildConfig flag and all four packaged APK entries. Release BuildConfig still forces
the native flag false even when the property is supplied. With one connected ARM
Android device, `tool/run_native_android_acceptance_windows.ps1` runs the real
Flutter→MethodChannel→JNI acceptance suite and enables the WG/AWG availability probe.

Next gates: Android device/JNI execution, real WG/AWG handshakes and leak tests,
network handover/background/repeated-start-stop testing, then distribution-license
review. Mihomo API24 source-build work and OpenVPN3 JNI remain separate unfinished
tracks.
