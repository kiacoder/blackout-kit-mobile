# Native device liveness and build-recovery continuation

**Overall remains 26%. No APK, Android connection or production verification.**
This extends the gated WG/AWG source integration in
[NATIVE_ANDROID_INTEGRATION.md](NATIVE_ANDROID_INTEGRATION.md).

## Build recovery: actual outcome

The official `gradle/gradle-distributions` release `v7.6.6` was found; its binary
asset is ID `269935142` (128439774 bytes). Download failed when GitHub redirected
to `release-assets.githubusercontent.com`, outside this workspace's permitted
hosts. No Gradle archive was accepted or executed. The diagnostic log has its
signed download URL redacted.

GitHub code/repository and npm registry searches did not establish a trustworthy,
compatible Flutter/Dart binary SDK. Old/incompatible SDKs and unrelated packages
are not substitutes. No unknown SDK binary was executed. Flutter/Dart remain
missing; Gradle dependency resolution, Flutter tests and debug APK remain unrun.
The previously recovered development API34/build-tools layout remains available.

## Implemented liveness path

* The disposable pinned JNI bridge gains a secret-free `wgIsClosed` /
  `awgIsClosed` method. It checks the device's `Wait()` channel without blocking,
  under the same handle mutex as start/stop. Unknown handles report closed.
* Native availability now probes the extended ABI with invalid handle -1 before
  any descriptor is transferred. Old libraries cannot silently run without
  monitoring. Staging also rejects builds without the new export.
* `NativeTunnelLifecycle` tests for closure during startup and exposes a guarded
  closure check. Unknown/error status is treated as closed; it does not discard
  the owned handle. Stop still retains ownership if cleanup fails.
* `BlackoutVpnService` polls every two seconds while the native session is
  current. JNI checks run on the existing serialized session worker, not the
  main/UI thread. No native settings or keys are returned to Kotlin.
* Closure stops the owned native handle and feeds the existing failure handler.
  With hold-on-failure requested, the service retains its own TUN descriptor
  and reports blocked; otherwise it attempts full teardown. Polls are cancelled
  on teardown, and generation/identity checks reject stale-session callbacks.
* **Scope:** an open device is NOT evidence of a handshake, valid remote server,
  traffic forwarding or DNS success. Down/up or network loss need not close the
  device. OS process death cannot be recovered or detected by an in-process poll.
  Fatal worker stalls that do not close the device are also outside this signal.

## Executed checks

* Four native libraries rebuilt (WG/AWG × ARM64/ARM32), API24 metadata gates and
  **seven JNI exports per library**, including the new liveness entry point.
* Narrow Android service/plugin API compilation passed. This is not Flutter
  Java/Dart compilation, Gradle resource processing, or an APK.
* **13** standalone JVM ownership/liveness checks passed with fake native calls.
* **12** real JUnit tests passed without Gradle (previous seven plus five new
  `NativeTunnelLifecycleTest` cases in the app's actual `src/test` tree).
* Existing **30 host**, **15 parser**, and **33 Python** checks passed again.
* AWG full race suite: **26 top-level passed, two upstream skips**. WG full race
  suite: **21 passed, one upstream skip**. Both now include a real upstream
  device test verifying Wait remains open across down/up and closes after
  device.Close; repeated Close remains safe.
* AWG stress: 20 deterministic first-read tests + 20 upstream packet tests pass,
  with no packet retries or weaker assertions.
* Both engines: **ten isolated Linux kernel-TUN checks each pass** again.
* Negative staging test: older JNI ABI rejected. Four rebuilt libraries staged
  successfully. Previous staged artifacts preserved at
  `.cache/native-tunnel-jni-prehealth`; original build outputs retained.

Exact artifact and private-log hashes are in `NATIVE_LIVENESS_RESULTS.json`.
Raw test logs remain in ignored `.buildlog`; no server/private configuration was
used. All added test keys/peers are synthetic upstream fixtures.

## Still required

* Obtain the pinned Flutter/Dart/Gradle development environment through an
  authorized private source; resolve dependencies, run Flutter/Gradle suites,
  and build the opt-in debug APK. No public publication or remote runner invoked.
* Android tests of actual FD ownership, native closure injection, stale callbacks,
  kill-switch routing, protection failures and error delivery. Source compilation
  and host mocks do not validate these behaviors on Android.
* Physical WG/AWG connections, TCP/UDP/DNS, network switching, reconnect,
  background/suspend and repeated start/stop/resource cleanup.
* Further license/security and simultaneous Go-runtime review before distribution.

Default-off debug gate and forced-off release behavior are unchanged. Mihomo is
still disabled. minSdk24 is unchanged. The accepted 66-file inventory remains
byte-for-byte unchanged, and nothing was pushed or published.
