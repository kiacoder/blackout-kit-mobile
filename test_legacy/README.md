# Legacy tests — quarantined, not deleted

These 13 files (3,434 lines) were moved here and renamed to `*.dart.broken` on
2026-09-19 because **they did not compile, and therefore had never run.**

## Why they were moved

`dart analyze test/` reported **387 errors** across them, in these categories:

| Count | Error | Example |
|-------|-------|---------|
| 118 | `undefined_named_parameter` | `WireGuardConfig(protocol: ..., displayName: ...)` — the real class takes `name`, `rawUri`, `privateKey`, `address`, `gateway`, `dns` |
| 105 | `missing_required_argument` | `name`, `gateway`, `dns` omitted from every `WireGuardConfig(...)` |
| 97 | `undefined_getter` | `ConnectionController.connectionState`, `.connectedSince`, `.killSwitchEnabled`, `ConfigController.sortOption`, `.error`, `.lastRefreshTime` |
| 35 | `undefined_method` | `ConfigController.filteredConfigs()`, `RxMap.add()`, `RxMap.reduce()` |
| 32 | `argument_type_not_assignable` | passing `List<TestResult>` where `Map<String, TestResult>` is expected |
| 4 | `undefined_function` | `OpenVPNConfig` — the real class is `OpenVpnConfig` |

They were written against an imagined API that does not match this codebase:
`Config` is abstract here, `TestResult` has no `reliability`/`timestamp`
constructor parameters, and several controller members they assert on never
existed.

Because a Dart test file that fails to compile aborts the entire `flutter test`
run, their presence meant **no test in the project could execute**. A suite that
cannot run is worse than no suite, because it looks like coverage.

## What replaced them

`test/` now contains a smaller suite that actually compiles and runs, focused on
the highest-risk logic:

- `test/xray_config_test.dart` — Xray JSON generation (the new engine path)
- `test/vpn_session_options_test.dart` — builder-time option validation
- `test/config_parsing_test.dart` — share-link parsing for every protocol

## What to do with these

They are kept because they encode intent worth recovering. If you want to
restore any of them:

1. Move the file back to `test/` and drop the `.broken` suffix.
2. Rewrite the assertions against the real API — the tables above name exactly
   which members were wrong.
3. Only keep assertions that test behaviour which exists. Several of these
   files assert on features that were never implemented (see the split
   tunneling and DNS leak prevention integration tests in particular, which
   asserted against method channels that had no native handler).
