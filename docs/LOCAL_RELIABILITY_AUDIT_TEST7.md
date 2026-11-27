# Local reliability audit — Native Test 7

Research or checkpoint record; preserved at its original scope. For the published version and current acceptance limits, see [CURRENT_STATUS.md](../CURRENT_STATUS.md).

Date: 2026-11-24. Scope: the isolated PR20 worktree, including the changes
from Native Tests 4–6. This is a source review plus local regression and
build validation, not an exhaustive device or security certification.

## Findings addressed

- Serialize liveness checks and attach them to the active session epoch;
  ignore late results after disconnect, replacement, or controller close.
- Reject late connection/website success after scan cancellation. Stop
  scanning when rejected-candidate teardown fails.
- Invalidate verification on native stop/error notifications. Ignore an
  unknown native status response instead of treating it as a stop. Do not
  promote adopted sessions to known-working before verifying them.
- Normalize website results to the requested host set; missing, ambiguous,
  and unsolicited results cannot satisfy the threshold.
- Keep unsupported Android-specific verification off iOS. Manual connection
  tests use live traffic checks rather than endpoint TCP reachability.
- Correct progress accounting and distinguish the number of attempted
  configurations from the total candidates in shortlist/hybrid mode.
- Serialize configuration writes, bulk writes, deletes, and clears.
  Duplicate attribution writes do not inflate new-profile counts.
- Prevent duplicate repository refreshes and deletion during a pending
  refresh. Preserve source enable/disable changes during refresh.
- Single-flight file picker and centralized import-dialog ownership;
  guard delayed UI callbacks and reject oversized file imports.
- Localized status copy in English, Persian and Chinese.

## Local validation

- Flutter: 575 passed (including new behavioral regressions).
- Android JVM: Gradle testDebugUnitTest succeeded.
- Analyzer: no errors/warnings; informational lints remain.
- APK: native-enabled side-by-side debug, ARM64 and ARMv7.
- SHA256: 481d7b722cfae31015302a1db2d1a9f3449f2e76fc7e0bc4de4ebffc698dcf1d
- APK size: 154587449 bytes.
- GitHub CI not triggered.

## Remaining acceptance gates

No device handshake, data-path, DNS or filtering diagnosis is established
by the local suite. Test authorized known-good endpoints on a device
with and without the affected network; inspect sanitized handshake and
traffic evidence, VPN route and socket behavior, disconnect/reconnect,
split tunneling, kill switch, and network transitions. The Go runtime
family admission restriction remains. Public profiles may be expired,
shared, unauthorized or incompatible; import counts do not establish
connectivity. Production native-tunnel release gate remains disabled.
