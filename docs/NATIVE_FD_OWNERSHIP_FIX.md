# WG/AWG failed-TUN descriptor ownership fix

Overall **26%**. This continuation fixes a real native error-path bug; it does
not establish APK/device acceptance or justify a completion claim.

## Reproduced bug

Both pinned cores' `CreateUnmonitoredTUNFromFD` called `os.NewFile(fd, ...)` and
could then return an error from `Name()` / `initFromFlags()` without closing that
wrapper. The original JNI bridge called `unix.Close(fd)` on this error path.
The unreachable Go file retained a finalizer. After the raw descriptor number
was reused, that finalizer could close the replacement descriptor.

Two separate fixtures establish the problem:

1. `tun_fd_ownership_test.go` uses `/dev/null`: nonblocking setup succeeds, but
   TUNGETIFF fails. The new consumes-on-error invariant fails on both pristine
   cores because the original descriptor remains open after constructor return.
2. `legacy_fd_reproducer_test.go` reproduces the exact old bridge behavior:
   raw-close on error, open a replacement with the same descriptor number, run
   GC, allow the finalizer thread 100ms, check the replacement. **Both pristine
   engines failed with `old TUN finalizer closed the replacement descriptor`.**
   This is a diagnostic of the old contract, not a production test to run against
   the new contract. It is deliberately excluded from the regular test runner.

No packet assertions, timeouts or retry policy were weakened. The finalizer
window is only in the diagnostic reproduction; it is not a workaround in code.

## Fix and build coupling

`tool/patches/tun-consume-fd-on-error.patch` changes the constructor contract:
FD ownership is consumed on **all** returns. Early failure before `os.NewFile`
closes the raw FD; later failure closes the `os.File`, disarming its finalizer.
The adapted JNI bridge no longer raw-closes this constructor's error result.
Its separate invalid-UAPI path continues closing the complete device.
JNI string-acquisition failures still close their untransferred FD in C.

The same patch applies with zero fuzz to both pinned cores. Build/test scripts
use disposable checksum-verified source copies; pinned upstream trees and the
module cache stay unchanged. The build records the patch and bridge hashes.
The staging tool now requires matching source revision plus current bridge/core
patch hashes, not merely filenames and ABI symbols. Older ownership artifacts
were tested and rejected. Four current artifacts were successfully staged; the
older stage is preserved as `.cache/native-tunnel-jni-prefdfix`.

## Executed results

* Both engines fail the original ownership invariant and actual legacy
  replacement-FD diagnostic before the fix. Those logs are retained.
* Each patched engine: **20/20 top-level ownership stress tests passed** under
  `-race` (two tests × ten runs). The reuse test executes 100 checked rejection/
  reopen/GC cycles per run: **1,000 cycles per engine**, with actual descriptor
  number reuse asserted. These are stress iterations, not failure retries.
* Four JNI libraries rebuilt: WG/AWG × ARM64/ARM32, API24 metadata gates and
  seven expected JNI symbols each passed. Still not executed on Android.
* Expanded full race suite now includes the real core `tun` package:
  **AWG 35 pass / 2 upstream skips; WG 30 pass / 1 upstream skip**.
  Each total includes nine top-level TUN tests; counts are not directly
  comparable with the earlier suite that did not include that package.
* AWG packet/barrier stress passed again (20 + 20 top-level tests).
* Both engines again passed ten isolated Linux kernel-TUN checks each, including
  forwarding, outage/recovery and repeated teardown. No Android claim.

Artifact hashes, per-package counts and private-log hashes are in
`NATIVE_FD_OWNERSHIP_RESULTS.json`. No deployment credentials are used.

## Build/device access remains necessary

Further permitted-host SDK searches found cached version metadata and some
untrusted/incompatible SDK mirrors, but no verified compatible complete Flutter
SDK was accepted or executed. The pinned Gradle distribution remains blocked by
its release-asset redirect. No toolchain substitution or project version upgrade
was made to manufacture a passing build.

Completing the requested mission requires an authorized private environment
with the pinned Flutter/Dart/Gradle dependencies and an accessible physical
Android device, followed by actual WG/AWG server connections, traffic/DNS,
network switching, background/restart and resource cleanup tests. Existing
server authorization and license/security requirements still apply. No public
push, release, deployment, minSdk change, or fabricated result.

The accepted 66-file inventory SHA remains
`d50b371b134d61a1c2cbd1c04ca82e7b5cfe673d8204129d6a6f73e75bbda42a`.

## Local-only continuation after access clarification

The user selected **no external environment available**. Continue local work;
APK/device acceptance remains explicitly incomplete. Do not use public runners,
request secrets, execute unknown SDK binaries, or mark the project 100%.

The native runtime parser now rejects all-zero private/public identity keys
(the core's zero-private-key UAPI value clears identity) and duplicate public
keys that could overwrite earlier peer AllowedIPs. A zero PSK remains allowed
as the documented disabled-PSK representation. Numeric fields reject signs.
AllowedIPs are masked to network addresses for both Android routes and UAPI,
while interface host addresses are preserved. DNS validation is shared with
the service and requires nonempty, non-loopback/non-multicast/non-unspecified
numeric DNS addresses covered by installed routes. This is runtime validation;
factory imports, stored profiles and export formats are not modified.

Latest local results: **24 parser**, **17 standalone JUnit**, **13 ownership**,
**30 host**, **33 Python** checks pass; service/plugin API compilation passes.
Five parser/routing JUnit cases are in the app's actual src/test tree. Flutter
and Gradle remain unrun. Initial parser test execution failed because a newly
written synthetic key fixture decoded to 35 bytes, not 32; corrected the fixture,
kept the rejecting assertion, and preserved the failed log. No real key was used.

See `LOCAL_ONLY_VALIDATION_RESULTS.json` for log hashes. Current overall remains
26%; all physical Android and full-build gates above remain in force.
