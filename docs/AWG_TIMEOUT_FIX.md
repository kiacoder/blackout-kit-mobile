# AWG first-read/configuration timeout: reproduced cause and patch

Research or checkpoint record; preserved at its original scope. For the published version and current acceptance limits, see [CURRENT_STATUS.md](../CURRENT_STATUS.md).

Overall remains **26%**. This is native-core progress, not Android app integration.
No APK, physical-device connection or server deployment is claimed.

## Cause

The pinned AWG core starts `RoutineReadFromTUN` in `NewDevice`, before initial
UAPI configuration. The reader obtains transport padding S4 and computes the
payload offset **before** its blocking TUN read. Initial configuration can then
change S4 from zero to 25 while that read remains blocked. On return, the old
padding and offset were retained for the outgoing packet although the receiving
peer expects the configured padding. This explains the intermittent return-packet
timeout. Atomic padding storage prevents an unsynchronized memory access, but
does not make the pre-read snapshot valid across configuration.

`tool/go_backend_tests/awg_read_barrier_test.go` forces the first reader to enter
before configuration, using the actual upstream channel TUN and device helpers.
The unpatched core failed both ping and pong. The test has no packet retries,
extra handshake workaround or relaxed packet assertions.

## Patch and reproducibility

`tool/patches/awg-refresh-padding-after-tun-read.patch` refreshes padding after
Read, checks bounds and uses overlap-safe copy to move the payload if the offset
changed. The official upstream checkout and checksum-verified module cache remain
unchanged. Both `tool/build_android_go_backend.sh` and
`tool/test_native_go_backends.sh` apply the same patch to disposable verified
source copies, with zero patch fuzz. Android build provenance records patch hashes.

With the pinned sources and dependencies recovered:

```sh
bash tool/test_native_go_backends.sh awg .cache/references/amneziawg-android --kernel
bash tool/test_native_go_backends.sh wireguard .cache/references/wireguard-android --kernel
ANDROID_NDK_HOME="$PWD/.cache/toolchains/android-ndk-r22" \
GO_BACKEND_ROOT="$PWD/.cache/toolchains/go-awg" \
bash tool/build_android_go_backend.sh awg .cache/references/amneziawg-android NEW_OUTPUT_DIRECTORY
```

The Go root must first have the pinned upstream boottime patch applied. See the
build script's checksum/reverse-patch checks. These are development-only tools.

## Executed evidence

See `AWG_TIMEOUT_FIX_RESULTS.json` for exact counts, hashes and artifact metadata.
Private raw logs are under `.buildlog`; they are not published.

* Unpatched deterministic reproduction: failed ping and pong (historical failure
  preserved, not erased by subsequent passing results).
* Initial patched stress: 20 barrier + 20 original upstream packet tests passed
  under `-race`.
* Reproducible patched runner: 24 top-level tests passed, two upstream skips;
  52 passing test/subtest events. Includes the original core suites and additional
  packet/parser/barrier tests. No failure or detected race.
* Runner stress: another 20 barrier + 20 original packet tests passed under `-race`.
* S4 variants 0, 1, 64, 1000: each passed five race-enabled runs (20 subtests;
  five parent tests). These test initial configuration, **not live rekey or hot
  padding updates**.
* Patched AWG: ten isolated Linux kernel-TUN checks passed, including TCP, UDP
  DNS, link outage/recovery, three start/stop cycles and TUN removal.
* Standard WireGuard comparison: 20 top-level tests passed under `-race`, one
  upstream skip; ten Linux kernel-TUN checks passed.
* Hardened AWG and WG bridges compiled for ARM64 and ARM32, API24 metadata gates
  and all six JNI exports passed. No binaries packaged into the app.
* New Kotlin profile parser: 15 JVM checks passed. Existing 30 host tests and
  33 Python tests passed again.

A local padding-variant test invocation initially failed compilation because the
private copied core contained the same barrier test under two filenames. The
older private copy was moved aside, and the test passed. Also corrected the
local gofmt executable path. Neither issue was a core packet failure.

## JNI changes, not yet service integration

`tool/prepare_android_go_bridge.py` adapts disposable pinned JNI source copies:
serializes handle operations, closes the device on invalid UAPI configuration,
removes filesystem UAPI and its nil-close risk, disables native profile/error
logcat and signal-stack output, and closes the transferred FD if JNI cannot
acquire either input string. Both Android architecture builds compile this code.
Runtime ownership and shutdown still require Android tests. Both libraries still
have the upstream `libwg-go.so` name: **do not co-package them**.

`NativeTunnelConfig.kt` is a bounded, strict WG/AWG config-to-UAPI parser. It
rejects hooks, unknown/duplicate fields, invalid keys/addresses/ranges and WG
profiles containing AWG fields. Address/DNS parsing does not resolve hostnames;
endpoint resolution is separate, intended before TUN installation. It has no
secret-bearing generated `toString`. It is **not wired into the service yet**.

## Remaining gates

The reproduced initial-read defect is fixed in the tested source/build path.
This does not establish all AWG lifecycle behavior as correct. Live parameter
changes, Android protected sockets, JNI FD ownership on real failures, resource
leaks, network switching and repeated Android shutdown remain unverified.

Next: distinct library packaging/entry points; actual BlackoutVpnService and
Flutter channel wiring using profile addresses/routes/MTU; protected socket and
TUN ownership; fail-closed cleanup; full Flutter/SDK/Gradle recovery and debug APK;
then physical Android integration tests. Existing Xray/sing-box and the accepted
66-file inventory remain untouched by this fix. No minSdk increase or publication.
