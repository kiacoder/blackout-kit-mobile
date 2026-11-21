# Preservation, build and lifecycle review — 2026-11-16

Overall remains **26%**, not a working new Android engine release.

## Git source of truth
The active branch is arena/d58a3d0b-blackout-kit-mobile. `git log` and reflog show
base 9c4213d, clone, and branch checkout only. `git cat-file` cannot resolve the
historically reported 563b57b, 5a7b6c9 or 86e81c7. `git fsck --full --no-reflogs`
finds dangling blobs but no recoverable later commits. This establishes what is
available locally, NOT why another session reported commits. No history was
rewritten, reset, garbage-collected, or reconstructed. Current tracked changes and
untracked implementation files are authoritative. No push/PR/fork/release occurred.

`CHANGE_REVIEW_INVENTORY.json` inventories SHA-256 and line counts for all changed
and new source/doc files at this review checkpoint. It includes untracked files,
which ordinary `git diff --stat` omits. The previous 3,317-addition figure is not a
complete or current inventory. Generated binaries/cache/build logs are excluded.

## Review and fixes
Reviewed tracked changes in engine selection, service lifecycle, plugin callbacks,
configuration parser/export/editor, catalogue, build gate, dependency lock and
security docs; inspected added lifecycle/checker/factory/export/test/build tools.
Automated inventory and secret scanning cover the broader source tree. This is not
an independent security audit or proof that every native dependency is safe.

Fixed during review:
* Factory rejected app JSON raw-document batches and Mihomo JSON. Full WG/YAML/JSON
  documents now remain intact; nested batches are bounded, mixed-engine objects
  rejected. Four new tests; 29 Python regressions pass.
* Concurrent disconnect could overwrite a global callback. Plugin now rejects an
  overlapping request, clears only its own callback, cancels its watchdog, and
  settles exceptions once. Connect is blocked while its disconnect is pending.
* Engine-death cleanup failures could skip UI publication. They now report error
  without declaring clean shutdown. TUN descriptor close failures mark cleanup failed.
* Launcher shutdown could call unbounded nativeWaitPid after failed signals.
  NativeChildStop now uses monotonic bounded TERM/KILL polling; unresolved PID and
  process handles are retained. Four added host tests include a real process,
  timeout/escalation, interrupt restoration and no signaling after reap.
* Removed URL and exception-message content from tunnel-fetch failure logging.

Remaining lifecycle risks require device testing/review: cross-plugin reattachment,
old/new service-instance overlap around destruction, JNI calls that never return,
monitor-thread PID ownership/reaping, and engine wrapper stop methods that swallow
errors. NativeChildStop tests do NOT execute Android JNI waitpid or pass a TUN FD.

## Secret and licensing review
Ran detect-secrets 1.5.0 across source (excluding .git, caches, logs, lockfiles and
SVG). 24 files flagged; values were not printed. Categories include release hashes,
synthetic test credentials, documentation placeholders, build IDs and public WARP
peer key. No newly exposed real credential confirmed. Automated detection can miss
secrets; no general clean-security certification is claimed.

Existing raw native logs, exception messages elsewhere, and arbitrary trusted full
profile directives remain concerns. Root MIT does not cover distributed native
engines. Mihomo GPL-3.0 corresponding source/notices/app-combination obligations,
sing-box terms, AWG/WG component licenses, and OpenVPN3 licensing must be resolved
before distributing combined binaries. Mihomo default remains OFF; no native
candidate was added to jniLibs. Android candidate API34 is not minSdk24-compatible
by assumption; rebuild/test against the supported API floor.

## Build environment and evidence
Private runner enumeration was retried: GitHub API returns 403. No private access
route or machine authorization endpoint is available. No remote build dispatched.
Additional npm/GitHub tool searches did not yield a verified complete Flutter/Dart,
JDK, SDK/NDK installation. JRE17/Kotlin/API jar are still narrow-check tools only.

Recovered seven official Flutter Java declarations at engine revision
b8800d88be4866db1b15f8b954ab2573bba9960f, verifying Git blob IDs before use.
`tool/fetch_flutter_compile_api.py` reproduces recovery without executing third-party
install scripts. `CHECK_FLUTTER_PLUGIN=true tool/check_android_engine_sources.sh`
now type-checks VpnPlugin along with ten service/engine/helper files. Java declarations
are compiler inputs, NOT compiled embedding classes. Generated resource/BuildConfig
substitutes remain; no Flutter Java/Dart, AGP, manifest/resource or APK validation.

Actual reruns:
* 30 standalone Kotlin/JVM host tests PASS.
* 33 Python tests PASS: 29 configuration-factory plus four ELF artifact-gate tests.
* 11 actual Mihomo Linux loopback integration tests PASS.
* Eleven production Kotlin source files API-check PASS, including VpnPlugin.
* Python compile, shell syntax and git diff whitespace checks PASS.
* Full Flutter suite, Gradle JUnit suite, APK, Android device/network-change tests:
  NOT RUN. Two Kotlin warnings remain (redundant non-null assertion and deprecated
  Android IP_ADDRESS API); no compile errors.

`tool/private_android_build.sh --check` records missing tools, with no provisioning
or uploads. On an authorized private Linux host, configure Flutter3.24.0/Dart3.5+,
Java17 JDK, SDK API34/build-tools, NDK API24 compilers, CMake/Ninja, Python requirements,
and outbound Flutter/pub/Google/Maven/Gradle access; then use `--build` to run locked
pub resolution, analyzer, full test/ suite, factory tests, Gradle unit tests and DEBUG
APK build. This recipe is syntax-checked, not successfully executed end-to-end.
Physical device tests and signing/release approval are separate. Keep logs private.

## Next engineering gates
1. Complete build on authorized private toolchain; fix analyzer/Flutter/Gradle failures.
2. Test service recreation, disconnect/reconnect, JNI/TUN ownership and minSdk24.
3. Build reviewed Mihomo Android artifact; verify real TUN/bridge TCP/UDP/DNS/rules,
   network handover, groups, kill-switch and cleanup before changing its default gate.
4. Integrate official AWG in the single VPNService ownership model, then native WG,
   OpenVPN3 JNI and maintained sing-box/Xray. No placeholder engines were added.
5. Server audit/deployment still requires an authorized private SSH route; no existing
   server was contacted and no deployment credentials/profiles were fabricated.

## Android artifact gate follow-up
`tool/check_android_artifact.py` reads ELF program-note metadata without executing
an artifact. It checks ARM ABI, PIE type and declared Android API floor, failing
closed on missing/malformed metadata. The actual verified upstream ARM64 candidate
was rejected for API34 > minSdk24 (MIHOMO_ANDROID_COMPATIBILITY_RESULTS.txt).
Four synthetic ELF regression tests pass. The Android source-build recipe invokes
this gate before accepting artifacts; the recipe still has not completed a build.
Passing this gate does not prove dynamic-symbol, 16-KiB-page or device compatibility.
