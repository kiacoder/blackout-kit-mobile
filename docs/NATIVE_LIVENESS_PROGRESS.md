# Native device liveness and build-recovery continuation

**Current checkpoint: native-enabled DEBUG APK packaging plus JNI/coexistence on a
physical ARM64 Android device are proven; real WG/AWG tunnel traffic and production
readiness are not.** This extends the gated WG/AWG source integration in
[NATIVE_ANDROID_INTEGRATION.md](NATIVE_ANDROID_INTEGRATION.md).

## Build recovery: actual outcome

The official `gradle/gradle-distributions` release `v7.6.6` was found; its binary
asset is ID `269935142` (128439774 bytes). Download failed when GitHub redirected
to `release-assets.githubusercontent.com`, outside this workspace's permitted
hosts. No Gradle archive was accepted or executed. The diagnostic log has its
signed download URL redacted.

That earlier build-recovery blocker is now superseded on the Windows development
host: Flutter 3.24/Dart, Java 17, Android API34/build-tools/platform-tools and
Gradle dependency resolution are usable. The full Flutter suite passes 551/551,
CI-style analyze exits 0, and native-enabled debug APK packaging succeeds. A Redmi
13 (arm64-v8a, Android 16/API36) now runs the physical acceptance suite. Separate
WG/AWG Go shared libraries reproduced `fatal error: addspecial on invalid pointer`;
a combined single-Go-runtime library removed that failure and the suite passed 7/7.

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

* The combined `libblackout-tunnels.so` runtime was rebuilt for ARM64/ARM32,
  passed API24 metadata gates, and exports all **fourteen WG+AWG JNI methods**,
  including both liveness entry points. Earlier separate libraries remain
  historical evidence but are no longer staged.
* The earlier narrow Android service/plugin API compilation passed and is now
  superseded by successful Flutter analysis/tests, Gradle app-module tests, and
  normal plus native-enabled debug APK builds.
* **13** standalone JVM ownership/liveness checks passed with fake native calls.
* The actual Gradle app-module unit suite now passes **33/33** with zero failures,
  errors or skips. It covers native lifecycle/FD/socket failure paths, parser
  hardening, atomic callback replacement, plus `VpnSessionExecutorTest` cases for
  nested `forCurrent()` callbacks, stale-ticket suppression, stop during a
  blocking start, and stop completion after a newer generation supersedes it.
* Earlier Linux evidence includes **30 host**, **15 parser**, and **33 Python**
  checks passing. The current Windows all-tool Python run is not counted because
  that interpreter lacks PyYAML and NTFS does not expose the POSIX `0700` mode
  expected by the security-permission test; those tests remain unchanged.
* AWG full race suite: **26 top-level passed, two upstream skips**. WG full race
  suite: **21 passed, one upstream skip**. Both now include a real upstream
  device test verifying Wait remains open across down/up and closes after
  device.Close; repeated Close remains safe.
* AWG stress: 20 deterministic first-read tests + 20 upstream packet tests pass,
  with no packet retries or weaker assertions.
* Both engines: **ten isolated Linux kernel-TUN checks each pass** again.
* Staging validates all fourteen JNI exports directly from the combined ELF and
  Gradle rejects stale separate WG/AWG libraries. The dual-runtime crash artifacts
  are preserved only as ignored local evidence; the active staging contains one
  combined runtime per ABI.

Exact artifact and private-log hashes are in `NATIVE_LIVENESS_RESULTS.json`.
Raw test logs remain in ignored `.buildlog`; no server/private configuration was
used. All added test keys/peers are synthetic upstream fixtures.

## Still required

* Physical Android validation of actual FD ownership, native closure injection,
  kill-switch routing, socket-protection failures and error delivery. Host/JVM
  tests now enforce the state-machine contracts, but do not prove Android FD or
  routing behavior.
* Physical JNI load/coexistence and repeated availability probes pass on the Redmi.
  Native WG/AWG start/stop, FD/socket ownership, real handshakes, TCP/UDP/DNS,
  network switching, reconnect, background/suspend and repeated start/stop remain.
* Further security review and real WG/AWG traffic acceptance are required before
  production distribution. The experimental test APK now carries the pinned native
  third-party notices; the rejected simultaneous-Go-runtime design is guarded against
  by staging and Gradle checks.

Default-off debug gate and forced-off production-release behavior are unchanged.
Mihomo is still disabled. minSdk24 is unchanged. Development commits remain on the
draft PR. A separately identified, side-by-side, debug-signed native test APK may
be published only as an experimental pre-release for the remaining physical-device
acceptance; this does not constitute production distribution readiness.
