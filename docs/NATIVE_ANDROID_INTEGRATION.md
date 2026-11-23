# WG/AWG Android source integration — private development only

> **Superseding liveness update:** [NATIVE_LIVENESS_PROGRESS.md](NATIVE_LIVENESS_PROGRESS.md).
> The previously missing device-closure monitor now exists in source; Android
> execution and kill-switch verification remain outstanding. Counts below are
> the earlier integration checkpoint, not the latest liveness run.

**Current checkpoint: source-integrated, freshly rebuilt, packaged, and JNI-tested
on a physical ARM64 Android device.** A dual-library design reproduced a Go runtime
fatal (`addspecial on invalid pointer`) on a Redmi 13, so WG and AWG now share one
`libblackout-tunnels.so` / one Go runtime. The physical-device acceptance suite passes;
real WG/AWG handshake, traffic, leak, handover and kill-switch acceptance remain open.

## Implemented

* `NativeTunnelEngine` connects the official, locally adapted JNI libraries to
  the existing `BlackoutVpnService`; no competing upstream VPN service is added.
* The native path establishes profile addresses, AllowedIPs routes and MTU,
  resolves endpoints before installing the TUN, and rejects DNS outside those
  routes. The caller's session DNS is used, including default WG/AWG profile DNS.
* The app UID is excluded during socket creation; including Blackout in an
  allowed-app list is rejected. Both available native UDP sockets must then pass
  `VpnService.protect`. The app exclusion covers the startup interval before
  protection; native startup is not claimed to protect before `device.Up()`.
* `NativeTunnelLifecycle` owns the native handle and a detached TUN duplicate.
  JNI consumes that duplicate on both normal and error returns. Missing JNI
  entry points close the undelivered FD. Protection failure stops the native
  device; failed stop retains ownership and prevents replacement. Service
  cleanup runs through the existing serialized session executor.
* Flutter sends the original `.conf` rather than a lossy regenerated profile,
  retaining all peers and modern AWG parameters. Native validation rejects
  unsupported fields/hooks. AWG remains distinct from standard WG. When the
  native WG gate is off, existing Xray WG routing remains unchanged.
* Native errors use fixed safe messages. Endpoint resolver exceptions are
  normalized at the config/UAPI boundary so resolver diagnostics cannot echo
  a user-supplied hostname. VPN revocation atomically takes the one-shot connect
  callback and dispatches it on Android's main looper because onRevoke() is not
  guaranteed to run there. No profile files or raw native logs are added. The
  native profile extra is removed from the received Intent. JVM/Go strings
  cannot be reliably zeroized; no zeroization guarantee is made.
* Native tunnels have no SOCKS listener. Exit-IP lookup returns unavailable
  instead of probing a stale listener or making a direct request from the
  excluded app UID and falsely reporting its address as the tunnel exit.
* WG/AWG share one `libblackout-tunnels.so` so Android loads only one Go c-shared
  runtime. Both original JNI class/method names remain exported; R8 keep rules
  protect those names. `GetConfig` is deliberately not exposed to Kotlin.

## Private debug packaging

Disabled by default: `ENABLE_EXPERIMENTAL_NATIVE_TUNNELS` requires the Gradle
property `enableNativeTunnels=true`. Release builds explicitly force it false.
Libraries are sourced only from a debug source set under ignored `.cache`;
no binary is downloaded at runtime or committed to tracked jniLibs.

After rebuilding the combined runtime with `tool/build_android_combined_tunnels.sh`:

```sh
python3 tool/stage_native_tunnels.py .cache/combined-tunnels-build
# Canonical debug packaging path; passes the Gradle property explicitly:
cd android
./gradlew :app:assembleDebug -PenableNativeTunnels=true
```

On Windows, `tool/build_native_debug_windows.ps1` performs the same build and also
verifies the generated debug BuildConfig flag plus the combined library for both APK ABIs.
Passing `-SideBySide` additionally sets the debug-only application ID to
`com.blackoutkit.vpn.nativetest` and verifies it from the finished APK, allowing
the experimental test build to install beside the production app. Release builds
remain `com.blackoutkit.vpn` with native tunnels forced off. A plain `flutter build apk`
did not reliably propagate `ORG_GRADLE_PROJECT_enableNativeTunnels` on the tested
Windows Flutter host, so it is not the canonical opt-in command. For a connected
ARM device, `tool/run_native_android_acceptance_windows.ps1` runs the physical-device
integration suite with the native Gradle property and the `BLACKOUT_NATIVE_ACCEPTANCE`
Dart gate enabled.

Staging checks the build manifest hashes, binds each required source/patch
digest to its expected provenance path, enforces API/ABI metadata gates, and verifies
all fourteen required WG+AWG JNI exports directly from each ELF dynamic symbol table.
It does not trust a sidecar symbol list as evidence of the binary's exported lifecycle
ABI.
It requires both engine JNI surfaces in the same ELF for both ABIs and refuses to
replace existing staging. Gradle also rejects stale separate WG/AWG libraries to
prevent the dual-Go-runtime crash from returning. This is not license clearance or
production approval. The opt-in DEBUG APK packages the combined runtime for ARM64 and ARMv7.

## Executed checks

* The combined native runtime was rebuilt for ARM64 + ARM32 with API24 metadata
  gates and all fourteen WG+AWG JNI exports verified directly from each ELF.
* Kotlin JNI declarations inspected using javap: expected static native methods.
* The earlier service/plugin source API check passed against both the pinned API
  jar and recovered AOSP API34 jar. That narrow evidence is now superseded by the
  successful Flutter analysis/tests, app-module Gradle tests, and debug APK builds.
* Native ownership coordinator: **11 passing app-module JUnit cases** plus
  **13 standalone fake-backend checks**. These cover handoff, failed starts,
  single-stack socket protection, restart, redacted failures and retained failed
  cleanup; they do not execute JNI or Android FDs.
* Profile parser: **15 passing JVM checks**.
* Existing host suite: **30 passed**; the historical Python suite checkpoint
  was **33 passed**; standalone real JUnit suite: **7 passed**. The combined
  stager now has **5 focused unit checks** covering both-ABI/all-export gating,
  no partial staging, artifact hashes, required source digests and digest/path
  binding. The authoritative full Python count is left to the Linux factory CI.
* AWG full core race suite: **25 top-level passed, 2 skipped**, now including
  the initial-padding variants. Stress: **20 barrier + 20 upstream packet tests
  passed**. WG full core race suite: **20 passed, 1 skipped**.
* Both engines: **10 isolated Linux kernel-TUN checks passed each**, including
  TCP/UDP-DNS, outage/recovery and repeated teardown. Not Android networking.
* Flutter is now available on the tested Windows host. The full suite passes
  **550/550**, CI-style `flutter analyze --no-fatal-infos --no-fatal-warnings`
  exits 0, and `:app:testDebugUnitTest` passes **33/33** for the Blackout app
  module. The added app-module cases exercise native lifecycle serialization,
  stale-ticket suppression, start/stop cancellation ordering, FD/socket failure
  paths, endpoint resolver redaction, AWG/WG field separation, IPv6 endpoint
  formatting, unsafe profile syntax, and atomic one-shot callback replacement.
  The structural regression suite passes **22/22**, including explicit checks
  that VPN revocation takes the callback atomically and posts delivery to main,
  kill-switch engine death retains the live TUN only for an active hold request,
  the Android JVM suite remains a hard PR/release gate, and the native test APK's
  side-by-side application ID stays opt-in/debug-only.

`NATIVE_ANDROID_INTEGRATION_RESULTS.json` is retained as a **historical
pre-combined-runtime checkpoint**; its old separate WG/AWG artifact entries must not
be read as current release evidence. Current combined-runtime status is documented
in this file and `NATIVE_LIVENESS_PROGRESS.md`. Private raw logs remain ignored in
`.buildlog`.

## Build environment recovery and failures retained

Recovered pinned development JDK/NDK/Go/Kotlin again after excluded caches were
absent. Clean-cache native build initially failed because `go list -m` returned
no directory before module extraction. Build and test scripts now run
`go mod download` against the verified local proxy before `go mod verify`;
both clean-cache native builds then succeeded. Checksum verification remains on.

Recovered `msft-mirror-aosp/platform.prebuilts.sdk` revision
`3af7c93524be6f51e092b87b17f009f13ee98b43` using sparse paths `34/public`,
`tools/linux`, `tools/lib`. `tool/assemble_development_sdk.sh` constructs a
platform/build-tools layout from this tree, preserving mirror provenance and
explicitly labeling locally generated platform discovery metadata.

API34 platform jars/framework.aidl and build-tools35 are present. aapt2, D8,
apksigner and actual AIDL Java generation smoke checks pass. Initial smoke
commands incorrectly used AIDL `--version`, then the wrong fixture package path;
both were corrected, retaining failed logs and earlier assembly directories.
A log-counting command also initially rejected a Go download progress line;
counting was corrected to parse JSON records only, without changing test results.

The tested layout is `.cache/android-sdk-tested`. This is **not a complete
SDK Manager installation**: adb/platform-tools, emulator, accepted release
licenses and Gradle-requested build-tool compatibility/dependencies remain
unverified. Do not label it an official SDK distribution. No minSdk change.

The current Windows host has Flutter 3.24, Java 17, Android API34/build-tools,
and the API24 NDK compiler path needed for these development artifacts. A normal
debug APK and the opt-in native-enabled debug APK both build successfully. The
current native-enabled APK contains `libblackout-tunnels.so` for ARM64 and ARMv7 and
contains no separate `libblackout-awg.so` / `libblackout-wireguard.so` entries. Release BuildConfig was
separately generated with the opt-in property present and still forces the native
flag to `false`.

## Remaining acceptance gates

1. Real native WG/AWG start/stop, FD-ownership, socket-protection and error-path tests.
2. Real WG/AWG connection/handshake, TCP/UDP/DNS and no-leak tests.
3. Network change/reconnect, background/suspend, repeated start-stop and
   combined-runtime resource cleanup on physical devices.
4. Native fatal-error monitoring is not implemented. A retained service TUN
   should block traffic if its engine fails, but status/kill-switch behavior
   has not been proven on Android. No production reliability claim.
5. Hot endpoint/padding changes and secret-memory/distribution-license review.

Mihomo remains disabled. No WG/AWG server handshake was attempted in this device
acceptance run, and no release artifact was published.
