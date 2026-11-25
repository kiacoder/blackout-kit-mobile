# Project Ascension ? professional repository program

## Roadmap

| Phase | Focus | State |
| --- | --- | --- |
| 0 | Security remediation and PR #20 acceptance | In progress |
| 1 | Repository governance | Core settings active; migration/review pending |
| 2 | Supply-chain security | Initial gates implemented; CI and review pending |
| 3 | Code quality engineering | Initial quality gates; Android lint remediation pending |
| 4 | Advanced automated testing | Planned |
| 5 | Android device laboratory | Planned |
| 6 | Performance engineering | Planned |
| 7 | Reliability and privacy-preserving diagnostics | Planned |
| 8 | Release engineering | Planned |
| 9 | Documentation and branding | Planned |
| 10 | Community and organic growth | Planned |
| 11 | Project management automation | Planned |
| 12 | Independent trust and auditing | Planned |
| 13 | Shared Black Series engineering standards | Planned |

Do not treat planned capabilities as implemented. Each phase has independent
acceptance evidence. Track unresolved risks rather than accumulating badges.

## Phase 1 ? 2026-11-24

Baseline: public repository, sole admin @kiacoder, basic main protection,
existing contribution/security files and private reporting, discussions enabled.
Default Actions token is read-only; workflow approval of PRs is disabled.
No existing rulesets; no verified local commit-signing configuration.

Live rulesets created and read back from the GitHub API:

| Name | ID | Enforcement |
| --- | --- | --- |
| Ascension - protect main | 27996090 | Active |
| Ascension - release tag creation | 27996091 | Active |
| Ascension - release tag integrity | 27996092 | Active |

Main requires PRs, resolved review threads, linear history, up-to-date required
Tests check from GitHub Actions (app 15368), no deletion or force push, no
ruleset bypass actors. Zero required approvals is deliberate for a one-person
project; squash or rebase only. Separate rulesets restrict v* tag creation to
admins and prevent tag modification/deletion without disabling the integrity
rule. Emergency changes to rulesets require explicit admin authorization.

Environments production-release and android-release-signing have tag-only v*
policies and owner review. Self-review allowed deliberately while there is a
single maintainer. The new draft publishing job references production-release.
Signing environment is staged, not yet used for credential isolation.
CODEOWNERS, governance policy and PR review checklist added on the integration
branch. They are not effective on main until merged.

Pending: secure migration of Android signing secrets and isolated signing job;
verified commit signing setup; independent reviewer when available; immutable
releases after draft-first workflow merges; comprehensive aggregate CI merge
gate after path-filtered workflows are redesigned. Existing repository-level
signing secrets are unchanged. No test tag or public release created.

Phase 0 status at audit: latest build APK workflow succeeded; separate iOS
compile run failed because GitHub could not allocate a macOS hosted runner,
not because of a compile error. Failed job rerun requested. CodeQL and actual
MobSF/VirusTotal report review remain separate; do not merge PR #20 merely
because governance settings have been enabled.

References:
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners


## Phase 2 - supply-chain security, 2026-11-24

- All direct external workflow references pinned to full Git commit SHAs.
  All existing checkout steps disable credential persistence.
- New Supply chain security workflow: dependency review on PRs (high and
  critical introduced advisories fail), cargo-deny advisory/license/source
  policy, zizmor workflow analysis, OSV new-vulnerability PR scans and full
  scans, Gradle wrapper validation, tracked binary and action-pin integrity.
- OpenSSF Scorecard workflow: weekly/manual and integration-branch baseline
  push, JSON evidence artifact, publishing disabled until the baseline is
  reviewed. No score or badge claimed.
- Cargo Dependabot updates grouped weekly. No automatic merging.
- Gradle 7.6.6 all distribution pinned to official SHA-256:
  6ed4d467349e2d3f555a578829c4aeadd67d73e2ec5d213c2a62f8f2829d9fa9.
  Source: https://services.gradle.org/distributions/gradle-7.6.6-all.zip.sha256
  Existing wrapper JAR is a historical version; independent wrapper validation
  must confirm it is a recognized official wrapper.
- Machine-readable baseline for 12 tracked binary files, including the AAR
  and both nested JNI hashes, five native shared libraries, Gradle wrapper,
  and five historical APKs. CI verifies paths and hashes before any build in
  the existing Tests and APK workflows. A matching checksum proves unchanged
  bytes, not verified upstream source provenance or malware-free status.
- Six synthetic regression tests cover valid manifest, altered/unknown binary,
  duplicate entry, mutable action ref and allowed local action.
- Rust license policy permits observed permissive SPDX terms; this does not
  clear licenses of opaque native libraries. No advisory exceptions added.

Local validation: 12 artifact hashes match; six new tests pass; actionlint
passes all ten workflows. No new scanner result or complete CI verdict
claimed yet. The new supply-chain jobs are not yet added to the required
main ruleset; the existing mandatory Tests job now includes integrity.
Review results and then require stable checks. Independent tools may have
transitive container tags/installers outside our direct action pin check.
Gitleaks, Trivy, provenance reconstruction for historic prebuilt engines,
release secret migration, and public Scorecard publication remain follow-up.

Phase 0 evidence update: run 45421149333 succeeded, including the MobSF
step. VirusTotal logged unknown-file for all three APK hashes; this is not
an antivirus verdict. Full MobSF report review is still pending, and no
production merge or release is approved here.

References:
https://github.com/actions/dependency-review-action
https://github.com/EmbarkStudios/cargo-deny-action
https://github.com/google/osv-scanner-action
https://github.com/zizmorcore/zizmor-action
https://github.com/ossf/scorecard-action
https://github.com/gradle/actions


## Phase 2 repair and Phase 3 initial quality gates (2026-11-24)

First supply-chain runs: binary inventory, Gradle wrapper, Dependency Review
and OSV PR comparison passed. Full OSV scan reported nine RUSTSEC-2026-0574
through RUSTSEC-2026-0582 advisories against heapless 0.8.0. Updated smoltcp
to 0.13.1 (locked) and heapless to 0.9.4, adapted address types and immutable
receive-token API. Cargo tree confirms heapless 0.8.0 no longer resolved.
No advisory ignores. Full OSV/cargo-deny rescan is required.

Fixed initial scanner configuration: cargo-deny default manifest-directory
deny.toml discovery (removed invalid --config argument), Rust 1.99.1 runtime,
zizmor 1.30.1 (supported digest by pinned action), Scorecard default branch
only. The actual Scorecard assessment must run after merge; no score claimed.

Rust FFI: three public raw-pointer entrypoints now declare unsafe contracts
and document caller requirements. JNI uses explicit bounded unsafe calls.
Fixed stop signaling from plain/JNI threads without an ambient Tokio runtime
by sending the oneshot under a synchronous mutex; this does not establish
full device-level teardown or prove no overlapping session work. Added
three host regression tests (shutdown signal, null pointer rejection, bounded
NUL-terminated error copy). C ABI names and signatures unchanged.
Host tests: 16/16. Clippy: zero errors, four remaining warnings
(three constructor argument-count warnings, one chunks_exact suggestion).

Quality workflow: pinned Ruff 0.11.13 with upstream distribution SHA-256
hashes, focused correctness rules (syntax, undefined names, invalid flow);
Python compilation, Rust Clippy/tests, rustfmt on seven migrated Rust files.
No blanket formatting of legacy files. Existing Dart analyzer warnings
are now fatal in Tests and APK/iOS build; 202 informational findings remain.
Added .editorconfig and opt-in PowerShell local quality script; no automatic
Git hook installation. Broader Ruff rules, Dart formatting, Rust formatting
expansion, Kotlin linting and ShellCheck remain planned.

Android lintDebug baseline: 18 errors and 11 warnings. Most errors are
API 26 Process/ProcessBuilder calls in EngineCommands, EngineRunner,
SubprocessLifecycle and VpnPlugin despite minSdk 24. One AppLinkUrlError
in AndroidManifest.xml. Preserve API24 support; fix with reviewed compatible
process lifecycle and intent-filter handling, then make lint a CI gate.
No lint suppression or minSdk increase. Report is local in ignored build
output, not a committed artifact. Android device behavior still unverified.

Local validation: focused Ruff passes, seven-file rustfmt passes, actionlint
passes all 11 workflows, 12 tracked binaries unchanged. Android lint fails
as described. New scanner and quality jobs await CI; no production merge.


## Phase 2 workflow audit follow-up (2026-11-24)

GitHub checks on 479e0de: Python correctness, Rust Clippy/regression,
host tests, factory tests, dependency review, cargo-deny, artifact inventory
and full OSV scan passed. Workflow security analysis reported two implicit
Go caches and four insufficient Dependabot cooldowns. Disabled Go caching
in the iOS APK workflow and Swift CodeQL job; added seven-day version-update
cooldowns to all four ecosystems (security updates unaffected). Local
inventory and six regression tests pass. Fresh zizmor CI verification pending.
Android lint remediation and APK report review remain open; PR stays draft.


## Phase 3 Android lint gate (2026-11-24)

The prior workflow-security repair passed zizmor, full/PR OSV and cargo-deny
checks on b617895. Added ProcessCompat: API-24-safe liveness and bounded
monotonic waits, guarded API-26 force termination, fixed-size output drain
with no persistent diagnostics. Runner and probe retain unresolved process
handles; probe shutdown now runs off the UI thread. API 24/25 uses destroy()
when forcible termination is unavailable; actual teardown on those devices
remains unverified. Checker timeout remains failure, not proof of exit.
Restrict Open-with intent to content URIs and octet-stream/text/plain MIME
types, matching existing activity restrictions; other MIME types require
in-app import. Actual file-provider interoperability needs device tests.

Local Gradle testDebugUnitTest and lintDebug succeeded twice: 40 JVM tests
passed (four added), lint 18 errors/11 warnings -> 0 errors/9 warnings.
25 targeted Flutter structural tests passed. Added lintDebug to required
Tests workflow; fresh CI pending. Gradle still reports pre-existing Kotlin
metadata/AGP compatibility diagnostics despite successful tasks; coordinated
toolchain upgrade remains separate. No lint suppression or minSdk change.
Remaining lint warnings: backup attribute, device ID, redundant API guard,
Flutter theme resource and five launcher icon warnings. Device and APK
security review still required before merge; no release performed.


## Phase 3 Android warning and host CI follow-up (2026-11-24)

Host workflow on f83014f failed: standalone Kotlin source lists omitted
ProcessCompat. Added production source to host, narrow Android API and local
JUnit harnesses, with a host-only SDK-26 Build stand-in for JVM execution.
The narrow Android compile still uses the actual android.jar. Added a real
1 MiB subprocess output test; Linux host CI confirmation pending. Local
WSL has no JDK; Docker daemon unavailable, so Linux execution not claimed.

Replaced ANDROID_ID-derived XUDP key/public fallback with a persisted random
32-byte per-install key. Existing users rotate that key on first startup
after upgrade; device-level persistence/interoperability still unverified.
Added Flutter NormalTheme manifest metadata; removed redundant SDK guard.
Local Gradle testDebugUnitTest and lintDebug passed (40 JVM tests; 0 errors,
6 warnings). Remaining warnings: API-31 backup attribute (preserve protection)
and five launcher icon shapes (preserve branding pending design review).
AGP 7.4.2 supports compileSdk 33 officially, while app uses 34; lint also
reports Kotlin metadata 1.9 vs 1.7.1. Upgrade separately with wrapper
checksum, plugin compatibility, all variants and device tests. No warning
suppression, minSdk increase, merge or release.


## Phase 3 shell correctness and toolchain CI (2026-11-24)

Baseline e3c422d: both host CI jobs passed (31 tests and Android API
compile); APK and Tests passed. One separate iOS runner acquisition failed
with capacity notices; another iOS build passed. Candidate toolchain
37be23c passed GitHub Tests workflow 45437373000; full APK workflow
45443595453 is in progress. See ANDROID_TOOLCHAIN_MIGRATION.md.

Added tool/check_shell_quality.sh and a Code quality CI job using
Bash syntax validation plus ShellCheck severity=error for every tracked
.sh/.bash file. All 15 scripts passed local syntax-only checks; a malformed
script in an isolated test repository was correctly rejected (exit 2).
ShellCheck is not installed locally; hosted check still pending. Runner
ShellCheck version is logged; warning/style debt remains open. No build
pins changed in this PR, and no APK release or merge performed.


## Phase 3 Kotlin quality introduction (2026-11-25)

ShellCheck correctness jobs passed. Experimental toolchain APK and iOS
workflow 45443595453 passed, including APK signature/inventory checks and
security scanner execution; report review/device validation remain open.
Added standalone SHA-256-pinned ktlint 1.5.0 and Detekt 1.23.8 CLI tools,
with Python 3.11+ runner and dedicated Code quality CI job. Initial full
source audit found 1313 ktlint findings and 337 Detekt weighted issues.
Strict gate covers OneShotCallbackSlot.kt and GoRuntimeAdmission.kt after
formatting-only remediation; local strict checks passed. Full audit is
available with --audit and fails on outstanding findings. No baseline or
blanket suppression added. Expand strict scope in tested batches. Local
Ruff unavailable; CI validation and Android regression recheck pending.
No production merge or release. See ANDROID_TOOLCHAIN_MIGRATION.md.


## Phase 3 Kotlin cleanup batch (2026-11-25)

Full ktlint audit now passes across all 32 Kotlin files (1313 initial
findings to zero reported). Aligned Kotlin line length to 120. Six scoped
JNI naming exceptions preserve existing Rust ABI symbols; no global rule
disabled. Full formatting is now enforced in CI. Host fixtures moved into
package-matching directories; all script references updated.

Detekt weighted issues reduced 337 -> 128; MagicNumber and MaxLineLength
now report zero. Introduced semantic constants for wire encoding, protocol
limits, process timeouts and test fixtures. Removed unused Kotlin JNI
declaration (native implementation unchanged), replaced constant-return
log helper with a constant, and strengthened a host negative-stop test.
Strict Detekt scope expanded from 2 to 12 clean files; --audit still fails
on outstanding issues. No baseline or blanket exception suppressions.
Remaining debt includes 49 broad catches, 32 return-count findings,
complexity/long-method issues and exception handling. Do not mark Phase 3
complete or advance to Phase 4 until this cleanup is reviewed.

Verified: full Kotlin formatting and scoped Detekt pass, 575 Flutter
tests, 40 Android JVM tests, Android lint 0 errors/6 warnings, all 15
Bash syntax checks, binary inventory/action pin verification. Structural
assertions updated for whitespace, braces and named constants without
removing the underlying checks. Standalone Linux host tests and fresh
GitHub CI await verification. Old AGP metadata diagnostics persist;
experimental toolchain promotion and device tests remain pending.


## Phase 3 Detekt lifecycle and parser refactor (2026-11-25)

Prior fc60f32 Kotlin formatting/static-analysis and Linux host CI jobs
passed. Refactored native config section parser, field validation and
peer/interface validation into bounded helpers with unchanged checks.
Separated native TUN descriptor transfer from protection/ownership
checks, split JNI startup/availability guards, simplified bounded child
shutdown and SOCKS readiness retries while retaining interrupt semantics.
ProcessCompat now guarantees attempted child cleanup if output drain
startup fails via finally, rather than catching a generic exception.

Detekt full audit 128 -> 115 weighted issues; strict scope 12 -> 19
files. Ktlint remains fully clean; no new rule exceptions or baselines.
Added two JUnit parser regression tests (header order, duplicate fields,
case-insensitive headers and comments). Local verification: 42 Android
JVM tests, 575 Flutter tests, lint 0 errors/6 warnings, scoped Detekt,
full ktlint, binary inventory and diff checks passed. New CI pending.

Remaining 115 weighted issues: 48 broad catches, 25 return counts,
11 long methods, 10 complexity, 8 swallowed exceptions, 4 too many
functions, 3 parameter-list findings, 2 loop-jump findings, 2 nesting,
1 throws-count and 1 large class. Native Android device validation
remains outstanding. Phase 3 still open; no production merge or release.


## Phase 3 Detekt Android boundaries (2026-11-25)

Prior 68ba559 Kotlin and Linux host CI checks passed. Refactored
NetworkPlugin, MainActivity, UpdatePlugin and NativeConfigValidator.
Narrowed expected Android platform exceptions instead of broad catches;
separated APK signature verification, archive checks, permission and
installer launch without relaxing existing package/signature checks.
Added bounded import copying (5 MiB cap enforced during streaming),
unique temp filenames and cleanup for failed/oversized copies; added
four JVM tests. Provider calls may still block; Android device and OEM
behavior require verification. No new Detekt suppressions or baseline.

Detekt full audit 115 -> 94 weighted issues; strict gate 19 -> 25
files including the two new sources. Full ktlint, 575 Flutter tests,
Android JVM tests, Android lint, binary inventory and diff checks
passed locally. Fresh CI and device validation pending. Phase 3
remains open; no production merge or release.


## Phase 3 Detekt engine cleanup batch 4 (2026-11-25)

Prior 33cf005 Kotlin, host, Tests and both iOS CI jobs passed; APK
job was pending at inspection. Refactored Xray initialization/startup
branches and shared failed-start cleanup; simplified EngineRunner config
write validation and narrowed IO/security exceptions; extracted libbox
network description and narrowed network/package lookup exceptions.
Reorganized import provider/descriptor ownership in one method, preserving
API24 release and AutoCloseInputStream ownership. Both Recycle warnings
from batch 3 resolved without suppression.

Detekt 94 -> 83 weighted issues; strict scope remains 25 files. Full
ktlint, scoped Detekt, 46 JVM tests, 575 Flutter tests, 12 binary
checks and diff checks passed. Android lint 0 errors/6 pre-existing
warnings. Confirmed via javap that bundled Xray startLoop/stopLoop
declare generic checked Exception, so those catches remain flagged
until a deliberate boundary review. No additional Detekt suppressions.
Remaining 33 broad catches, 17 return counts, 10 long methods, 9
complexity, 14 other findings. Fresh CI/device validation pending;
Phase 3 not complete, no main merge or release.


## Phase 3 VPN service and plugin cleanup batch 5 (2026-11-25)

Prior af718dc hosted Kotlin, host, Tests and supply-chain checks passed;
APK and iOS builds were pending at inspection. Extracted connection
intent construction, consent dispatch and timeout scheduling from the
plugin. Grouped service request parameters in a private non-data class
(no generated configuration-revealing toString), preserving native
extra removal, callback capture and session ticket checks. Simplified
notification permission, HTTP status handling and IP matching control
flow. Detekt 83 -> 71 weighted findings; all three long-parameter-list
findings resolved. Strict scope remains 25 files. Full ktlint, scoped
Detekt, 575 Flutter tests, Android JVM tests and lint passed locally.
Remaining 33 broad catches, 11 return counts, 9 long methods, 7
complexity, 11 other findings. No new suppressions. Old toolchain
metadata diagnostics, native device validation and fresh CI remain
open. Phase 3 remains incomplete; no main merge or release.


## Phase 3 VPN service decomposition batch 6 (2026-11-25)

Prior df9af21 hosted Kotlin, host and supply-chain checks passed;
Tests/APK/iOS jobs pending at inspection. Split proxy interface setup,
engine activation, connected-state publication and engine-family dispatch.
Shared DNS setup across proxy/DNS-only paths; narrowed expected invalid
DNS, missing package and descriptor IO failures. Unexpected exceptions
now reach the outer setup failure handler. Preserved session tickets,
kill-switch listener ordering, DNS refusal, split-list exclusivity and
fresh-config requirement. Fixed API 33 permission warning with explicit
SDK guard and annotated helper. Updated stale-config source assertion
for when branch and ordering. Detekt 71 -> 61 weighted findings; strict
scope remains 25 files. Full ktlint, scoped Detekt, 575 Flutter tests,
46 Android JVM tests, lint 0 errors/6 pre-existing warnings, 12 binary
checks and diff checks passed. No new suppressions. Remaining 28 broad
catches, 10 return counts, 7 long methods, 6 complexity, 10 other
findings. Larger class responsibilities remain to be extracted; device
validation, toolchain promotion and fresh CI pending. No merge/release.


## Phase 3 engine and standalone test decomposition batch 7 (2026-11-25)

Prior b3c1105 hosted Kotlin, Linux host, Rust and supply-chain checks
passed; Tests/APK/iOS builds pending at inspection. Split standalone
engine, parser and ownership test harnesses into focused case groups
without removing test cases. All three now pass strict Detekt, raising
coverage from 25 to 28 of 34 Kotlin files. Local cached Kotlin 1.9.25
compiler verified 24 parser and 13 ownership cases on JVM and compiled
the Linux engine harness (execution requires Linux CI). Refactored
EngineRunner launch preparation, validated launch, native bridge spawn,
startup checks, SOCKS readiness and monitoring while preserving failure
cleanup and checks. Detekt 61 -> 52 weighted findings (five files).
Remaining: 27 broad catches, 9 return counts, 4 complexity, 4 function
counts, 3 long methods, 3 swallowed exceptions, 1 nesting, 1 large
class. No additional suppressions. Verified full ktlint, scoped Detekt,
575 Flutter tests, 46 Android JVM tests, Android lint and 12 binary
checks locally. Fresh Linux execution and CI, physical-device checks
and toolchain promotion remain pending. Phase 3 open; no merge/release.


## Phase 3 site verification decomposition batch 8 (2026-11-25)

Prior 53290a7 hosted Kotlin, Linux host, Rust and supply-chain checks
passed; Tests/APK/iOS were pending at inspection. Extracted SiteProbeRunner
from VpnPlugin, preserving native VPN Network binding, session checks
before and after requests and at result delivery, no native SOCKS fallback,
TLS validation, no redirects, bounded parallelism and HTTP status semantics.
Narrowed expected IO/argument/state/security and future exceptions,
restored thread interruption and cancel timed-out futures. Added two
JVM tests (missing native network fails without fallback, non-native
results unchanged), updated structural assertions and optional plugin
API compile source list. Detekt 52 -> 45 weighted findings; strict
scope now 30 of 36 files. Full ktlint, scoped Detekt, 575 Flutter tests,
48 Android JVM tests, lint 0 errors/6 warnings, binary inventory and
15 shell syntax checks passed. No additional suppressions. Remaining
25 broad catches, 7 return counts, 4 function counts, 3 swallowed
exceptions, 3 complexity, 2 long methods, 1 large class. Fresh CI,
physical-device VPN traffic verification, and toolchain promotion
remain pending. Phase 3 open; no production merge or release.


## Phase 3 native engine boundaries batch 9 (2026-11-25)

Prior 2fc03c6 hosted Kotlin, host, Rust and supply-chain checks passed;
Tests/APK/iOS were pending at inspection. Extracted EngineRunner launch
coordinator while preserving JNI names and runner-owned process handles.
Centralized failed-launch cleanup in finally; handle IO, permission,
interruption and linkage failures explicitly. Unexpected failures propagate
after attempted cleanup. EngineRunner now passes strict Detekt. Separated
libbox platform policy from Android queries, split native service startup,
and extracted Xray installation key handling. Removed several raw native
error and status messages from logs/UI to reduce credential exposure.
Verified actual bundled Java declarations with javap: libbox newService,
start and close, and Xray startLoop/stopLoop declare checked Exception.
Seven broad native-boundary catches remain flagged for review; no new
suppressions. Existing embedded-engine failed-stop ownership behavior
still needs explicit review and real-device tests.

Full Detekt audit 45 -> 33 weighted findings; four files remain:
VpnPlugin 15, BlackoutVpnService 11, LibboxEngine 4, XrayEngine 3.
Strict scope 31 of 36 files. Full ktlint, scoped Detekt, 575 Flutter
tests, 48 Android JVM tests, Android lint 0 errors/6 warnings,
12 binary checks and diff checks passed. Fresh CI, toolchain promotion
and physical-device validation remain pending. No production merge/release.


## Phase 3 embedded ownership batch 10 (2026-11-25)

Prior 3434811 hosted Kotlin, Linux host, Rust and supply-chain checks
passed; Tests/APK/iOS pending at inspection. Shared EmbeddedCoreOwner
assigns native handles before activation, retains them on failed close,
blocks replacement until cleanup succeeds, and serializes same-owner
operations. Xray probe cleanup checks ownership even when not running.
Libbox startup failure cannot fall back when native cleanup throws.
Removed unused Xray config retention; native failure categories remain
redacted. Centralized declared gomobile checked exceptions in embeddedCall
with interrupt restoration and no catch of fatal JVM errors (other than
expected linkage failures). One broad checked exception remains explicitly
flagged, not suppressed. Five new JVM tests cover owner retention, retry,
partial startup, interruption and error propagation. Service-level TUN
descriptor lifetime on failed native close and cross-engine concurrency
still require review; real-device behavior unverified.

Detekt 33 -> 27 weighted findings: VpnPlugin 15, BlackoutVpnService 11,
EmbeddedCoreOwner 1. Strict scope 34 of 38 Kotlin files; both embedded
engine files clean. Full ktlint, scoped Detekt, 575 Flutter tests, 53
Android JVM tests, Android lint, 12 binary checks and 15 shell syntax
checks passed. No additional suppressions. Fresh CI, toolchain promotion
and real-device tests pending; no main merge or release.


## Phase 3 service descriptor cleanup batch 11 (2026-11-25)

Prior bf8384e Tests, both iOS builds, Kotlin, host, Rust and supply-chain
checks passed; APK job pending at inspection. TunnelCleanup attempts
all engine stops before releasing TUN descriptors; failed engine stop
retains service-owned descriptors for retry. Removed premature close on
failed activation, report startup failure and retain foreground service
if cleanup is pending. IOException handling is specific and redacted;
three JVM regressions cover stop order, retry and linkage failure.
This is an ordering improvement, not proof of descriptor ownership
across native ABI, Android service destruction or process restart. Cross-
engine concurrency and real device checks remain outstanding.

Detekt 27 -> 23 weighted findings (VpnPlugin 15, BlackoutVpnService 7,
EmbeddedCoreOwner 1); strict scope 36 of 40 Kotlin files. Full ktlint,
scoped Detekt, 575 Flutter tests, 56 JVM tests, Android lint, 12 binary
checks and 15 shell syntax checks passed. No new suppressions. Plugin
decomposition deferred to next batch. Fresh CI and toolchain promotion
pending; no production merge or release.


## Phase 3 passive capability catalogue batch 12 (2026-11-25)

Prior 5f3ab78 hosted Kotlin, Linux host, Rust and supply-chain checks
passed; Tests/APK/iOS pending at inspection. Extracted EngineCatalogue
from the Flutter plugin. It reads packaged files and runtime ownership
without claiming or loading a native runtime. Preserved protocol lists,
restart requirements and experimental feature flags; absent native
directory no longer falls back to relative executable paths. Split
validation admission and asynchronous config checking. Added four JVM
catalogue tests and updated source checks and optional Android compile
source list. Detekt 23 -> 20 weighted findings (VpnPlugin 12, service 7,
EmbeddedCoreOwner 1); strict scope 38 files. Full ktlint, scoped Detekt,
575 Flutter tests, 60 Android JVM tests, Android lint, 12 binary checks
and 15 shell syntax checks passed. No new suppressions. Probe lifecycle
and service decomposition still pending, along with fresh CI, device
validation and toolchain promotion. No production merge or release.


## Phase 3 headless probe lifecycle batch 13 (2026-11-25)

Prior 703020d hosted Kotlin, Linux host, Rust and supply-chain checks
passed; APK/iOS/Tests pending at inspection. Extracted process-wide
ProbeEngineController from VpnPlugin, retaining the subprocess handle
on unsuccessful cleanup and serializing headless starts/stops. Added
worker-side live-VPN checks, port/config-size validation and child
liveness confirmation after SOCKS readiness. Native diagnostics remain
redacted. Updated structural assertion and optional API compile list.
Cross-engine admission between service and probe remains unresolved;
readiness is not proof of device traffic or listener ownership.

Detekt 20 -> 14 weighted findings (VpnPlugin 6, service 7,
EmbeddedCoreOwner 1); strict scope 39 files. Full ktlint, scoped Detekt,
575 Flutter tests, 60 Android JVM tests, Android lint 0 errors/6 warnings,
12 binary checks and 15 shell syntax checks passed. No new suppressions.
Fresh CI, physical-device verification and toolchain promotion remain
open. No main merge or production release.


## Phase 3 VPN setup paths batch 14 (2026-11-25)

Prior 09f02ca hosted Kotlin, Linux host, Rust and supply-chain checks
passed; APK/iOS/Tests pending at inspection. Separated native builder,
activation and status publication; split DNS-only interface opening
from DNS validation and retained no-route behavior. Simplified proxy
activation result handling and narrowed expected platform/network
exceptions in service and plugin. Redacted setup failure diagnostics.
Strengthened native routing structural test for resolver-before-TUN
ordering and app inclusion. Full Detekt 14 -> 6 weighted findings:
service class size/function count, plugin class size/function count/
dispatch complexity, one required checked native ABI boundary.
No new suppressions; strict scope remains 39 files. Full ktlint, scoped
Detekt, 575 Flutter tests, 60 Android JVM tests, Android lint, and 12
binary checks passed. Fresh CI, physical-device verification, cross-
engine admission and toolchain promotion remain outstanding. No main
merge or production release.


## Phase 3 Kotlin cleanup completion (batch 15, 2026-11-25)

Full ktlint and Detekt gates pass for all 43 Kotlin files. The staged
Detekt allowlist has been removed; the default and --audit commands
now run the same full scan. VPN plugin responsibilities are separated
into permission, connection, catalogue and diagnostic controllers.
Service responsibilities are separated into native/proxy setup,
engine selection, DNS-only setup, engine monitoring and foreground
notification components. No baseline or globally disabled rules.
One function-level TooGenericExceptionCaught suppression is documented
for embeddedCall: the shipped gomobile ABI declares java.lang.Exception
for newService/start/close/startLoop/stopLoop. Retain checked exception
translation and interrupt restoration without swallowing fatal JVM
errors. Existing scoped JNI naming exceptions remain. Unresolved
Detekt findings 337 -> 0; full formatting gate passes.

Added bounded retry for transient Maven download failures after prior
39202ef push CI returned HTTP 429 (PR equivalent passed). SHA256
validation and official Maven source unchanged. Mocked retry/404
checks passed. A temporary unused/magic-number Kotlin fixture was
rejected by the full gate, removed, and the clean gate passed again.
575 Flutter tests, 60 Android JVM tests, lint 0 errors/6 warnings,
12 binary checks and diff checks passed locally. Prior 39202ef APK,
both iOS builds, Tests, host, Rust, OSV and supply-chain jobs passed.
Kotlin cleanup complete; Phase 3 still has broader toolchain, existing
lint warnings and quality work. Fresh full CI and physical-device
validation remain open. No main merge/release.


## Phase 3 refreshed toolchain and scan review (2026-11-25)

Both 0638ded full Kotlin CI checks passed. Retrieved and verified all
three earlier toolchain candidate APK hashes, inventory and six
evidence hashes. ClamAV zero detections; MobSF score 46/100, four
high findings and ten warnings; VirusTotal not configured for that
run. See ANDROID_TOOLCHAIN_SECURITY_REVIEW.md for dispositions and
unresolved findings. Removed unused non-loopback cleartext exception
for the TUN address and added a regression assertion. Preserved
backup protections and launcher branding; six lint warnings remain.
Full Kotlin gate, 576 Flutter tests, 60 Android JVM tests, lint
0 errors/6 warnings and 12 binary checks passed locally.
Refreshed isolated AGP 8.5.2 / Kotlin 2.0.21 / Gradle 8.7 candidate
at f6925ca against 0638ded; Tests 45562485870 and build 45562490487
dispatched and in progress at inspection. Revalidate this policy
change on candidate before promoting. Main and PR toolchain pins
unchanged. Phase 3 remains open; no release.


## Phase 3 strict Android lint and vault recovery (2026-11-25)

All five legacy launcher PNGs regenerated from existing app artwork
with transparent padding and rounded silhouette, preserving original
color artwork and source/iOS assets. One narrow UnusedAttribute message
exception in app/lint.xml preserves intentional API31 dataExtractionRules;
allowBackup=false and fullBackupContent=false unchanged. No lint
baseline or global disabled checks. warningsAsErrors enabled. Local
:app:lintDebug exits 0 and reports No issues found. Old analyzer Kotlin
metadata diagnostic remains until AGP promotion.

Fixed vault state when keystore read fails: existing encrypted data
reports locked, not absent. Strictly validate 32-byte hex keys; do not
replace malformed key when encrypted data exists. Two new regression
tests; full Flutter suite 578/578 passed. Full ktlint/Detekt and 12
binary checks passed. Prior local JVM suite (60) passed on icon changes.

Isolated secure-storage migration worktree created at 5ec7b51; proposed
10.3.4 upgrade (9.x encrypted preferences migration must precede newer
versions which drop that backend). Local flutter pub get returned 69
with pub.dev authorization failure. No resolved lockfile, build or
key migration evidence; do not promote. Remaining MobSF findings
require a fresh scan, dependency mapping, device acceptance and
review; no claimed score improvement or production release.


## Phase 3 native configuration security follow-up (2026-11-25)

Refreshed f6925ca candidate Tests, APK and iOS builds passed. Prior
d00def9 hosted Kotlin, Rust and supply-chain checks passed at inspection.
Reviewed previous MobSF native mitigations (both packaged ABIs);
explicit C fdlauncher compiler/linker hardening built successfully.
Replaced fixed reusable subprocess config files with owned per-session
files for full tunnels and sing-box probes. Added three tests covering
unique files, replacement refusal and deletion retry; updated the
missing-config regression assertion and Android API source list.
Full ktlint and Detekt, 578 Flutter tests, 63 Android JVM tests, strict
Android lint (no issues), 12 binary checks, 15 shell syntax checks and
Android debug CMake build passed. Old analyzer metadata diagnostics,
legacy/crash residue, checker child ownership, cross-engine admission,
dependency and native provenance review, fresh CI, device validation
and current MobSF score remain open. See security review for details.
No main merge or release.


## Phase 3 engine admission and retired configuration cleanup (2026-11-25)

Process-wide EngineSessionAdmission now provides an identity-based
lease across foreground VPN and headless probe startup, operation and
cleanup. Foreign teardown never stops shared engines; failed cleanup
retains ownership and denies a competing start. Probe stop without
a probe lease is an idempotent no-op. Service instance destruction
with unsuccessful cleanup may require process recovery; no claim of
cross-process or physical-device validation. Added two concurrency
and identity admission tests. Engine config staging removes only
three obsolete fixed filenames (singbox.json, mihomo.json and
singbox-probe.json) in its private engine directory; refuses directory
or redirected-file cleanup and leaves current session and unrelated
files alone. Added two cleanup tests. Old process orphan detection,
unique crash residue and checker child ownership remain open.
Full ktlint/Detekt, 578 Flutter tests, 67 Android JVM tests, strict
Android lint and 12 binary checks passed locally. Existing AGP metadata
diagnostics remain pending toolchain upgrade; fresh CI and device
acceptance remain outstanding. No current MobSF score or release.


## Phase 3 native launcher parent-death and provenance review (2026-11-25)

Added Linux parent-death guard for JNI-launched tun2socks: install
PR_SET_PDEATHSIG before exec and reject mismatched parent PID. This
protects the launcher's direct child, not Java ProcessBuilder children
or arbitrary descendants. Linux parent-thread lifetime semantics
require an enduring service worker; Android device validation remains
open. Native setup now fails closed on JNI argument allocation, log
open, fd duplication and close-on-exec setup failures. Avoid Android
logging in the child between fork and exec. Added a Linux regression
for parent exit and mismatched parent; passed under Ubuntu WSL and
wired into pinned GitHub quality workflow. Existing higher-descriptor
inheritance, PID reuse/reaping race, older orphans and crash-residue
cleanup remain separate tasks.

Read-only Go module metadata and public checksum database review
identified tun2socks v2.7.0 and corroborated three upstream module
checksums; merged libbox still lacks exact source revision. See
NATIVE_ARTIFACTS.md. No binary hashes or engine versions changed.
Fresh hosted tests, Android device checks and MobSF/VirusTotal score
remain open; no production merge or release.


## Phase 3 native child identity and reaping (2026-11-25)

Replaced JNI-facing raw bridge PIDs with monotonic opaque tokens.
A native mutex serializes registration, polling/reaping and signaling;
exit status is cached, stale tokens are rejected, and only a confirmed
direct child may receive SIGTERM/SIGKILL. Removed unused blocking JNI
wait export. The ownership check assumes the launcher is the sole
reaper of its JNI child; arbitrary external waitpid callers and
platform behavior require device acceptance. Monitor captures its own
child token, Process handles, callback and cancellation flag; startup
rechecks child liveness after SOCKS readiness. Linux regression covers
stale token, invalid signal, cached status and non-child rejection.
Both prior parent-guard CI jobs passed. Local native lifecycle test,
Android debug CMake build, JNI export inspection, 578 Flutter tests,
67 JVM tests, strict lint (no issues), full ktlint/Detekt and 12 binary
checks passed. Existing test-environment Hive/wakelock diagnostics
and old AGP metadata messages remain. Native descriptor close loop
still stops at 128; defer full descriptor enumeration to a tested
follow-up. Java subprocess lifetime, crash residue, reproducible
builds, fresh scanner results and device acceptance remain open.
No main merge or release.


## Phase 3 native descriptor isolation (2026-11-25)

Removed the fixed 128 descriptor cutoff in fdlauncher. The forked
child redirects stdin to /dev/null, preserves its explicit TUN slot
3, and closes all higher descriptors using kernel getdents64 over
/proc/self/fd (no libc directory allocation after fork). Non-Android
Linux can use close_range first. Android deliberately avoids probing
the newer syscall because older seccomp policies may trap rather than
return ENOSYS. Unexpected enumeration/close failures refuse exec.
Linux regression exercises both dispatch and explicit proc paths,
258 high descriptors across multiple buffers, preservation of slot 3
and unchanged parent descriptors. WSL regression, final Android
debug CMake build, 67 JVM tests, strict lint (no issues), full Kotlin
quality and 12 binary checks passed. Prior native lifecycle hosted
checks passed. Flutter suite unchanged since prior 578-test pass;
not rerun in this C-only batch. Android device SELinux/seccomp and
actual fd behavior still require acceptance. Java subprocess death
handling, orphan residue, reproducible source builds and fresh
scanner results remain open. No production release.


## Phase 3 configuration checker ownership (2026-11-25)

All native config validators now share one process-scoped bounded
checker owner. A failed stop retains the actual Process and its
config path; the next check retries cleanup before launching anything.
Explicit CHECK_CLEANUP_PENDING outcome prevents a failed cleanup from
being reported as validation success. TransientEngineConfig refuses
to delete a checker-owned file until process exit is confirmed.
Plugin validation admission and file owner survive Flutter detach/
reattach; private filesDir/native-checks avoids cache eviction.
Two JVM regressions cover resistant-child cleanup, file retention,
retry and interrupt restoration. Structural timeout test updated to
check injected production functions and bounded cleanup. Full Kotlin
quality, 578 Flutter tests, 69 Android JVM tests, strict Android lint
(no issues) and 12 binary checks passed locally.

This is in-process ownership, not a complete app-death guard for
Java ProcessBuilder. The shared checker serializes calls; a competing
call can wait behind an active check. App-process crash residue,
long-lived subprocess parent protection, physical-device acceptance,
secure-storage migration, reproducible native builds and current
scanner verdicts remain open. No main merge or release.


## Phase 3 experimental subprocess supervisor (2026-11-25)

Added a standalone native supervisor candidate using a lifetime pipe
from its owner, not the lifetime of a Java launching thread. Child
gets a parent-death guard, isolated descriptors and /dev/null stdin;
no shell and no persistent diagnostics. Linux regressions cover
normal exit, pipe closure, TERM, forced supervisor death, launching
thread turnover and owner process death (6 passed). CI now runs them.

Opt-in debug packaging via -PenableProcessGuardExperiment=true was
verified in an assembled APK with ARM64 and ARMv7 ELF entries.
Candidate retained only in ignored .cache/process-guard-experiment/
app-debug.apk, SHA256 0a13f49be6eb69272662c1bb29f38d84f1781beb96592dd46a6ac63917da4fb1.
Default APK rebuilt and verified to exclude the candidate. Release
CMake configuration explicitly disables it; release inventory rejects
libprocess_guard.so, with regression coverage. Local Android build,
69 JVM tests, strict lint and 6 release-security tests passed; binary
inventory checks and Python compilation passed. Ruff unavailable
locally; hosted quality gate remains required. No attached Android
device found. The supervisor is NOT wired into ProcessCompat or
production engine launches. Android extraction/execution and lifetime
behavior must be tested before activation. Force-kill does not itself
prove descendants are reaped, and old crash residue remains open.
No production merge or release.


## Phase 3 supervisor device acceptance harness (2026-11-25)

Added platform Instrumentation runner and synthetic C child fixture
using a cross-process POSIX lock to prove child cleanup independently
of supervisor exit. Cases: propagated exit status, lifetime-pipe EOF,
TERM, launch-thread turnover, forcible stop (API26+). Fixture includes
a 30-second independent bound. No VPN credentials or network needed.
Opt-in debug build has distinct com.blackoutkit.vpn.guardtest package
and companion .test package. Windows acceptance script builds by
default; device execution requires explicit -RunOnDevice -DeviceSerial
and validates package identities, ARM ABI, API and exact pass marker.
Both APKs compiled, package identities verified with aapt, and both
ARM ABIs contain guard and fixture ELF entries. APKs retained under
ignored .cache/process-guard-acceptance/. Default APK rebuilt and
verified to exclude both executables. Release inventory rejects both;
six release-security tests and 12 tracked artifact checks passed.
69 JVM tests and strict lint passed; old AGP metadata diagnostics
remain. Prior hosted supervisor and Ruff checks passed. No device
attached, so instrumentation execution is NOT verified. Production
activation, actual app-process-death test on Android, crash residue,
secure-storage migration and fresh security scan remain open.
No main merge or release.


## Phase 3 pinned standalone Go candidate builds (2026-11-25)

Added source-pin build tool and four unit tests (all passed). Source
module checksums verified for tun2socks and sing-box. Tun2socks
ARM64 and ARMv7 API24 candidate builds repeated with matching hashes
on the same Windows host and shared caches. Build evidence retained
under ignored .cache/tun2socks-rebuild-c. No historical binary
replaced. Candidate dependency graph differs from historical
x/crypto and x/sys; promotion blocked pending reviewed lock and
independent/device validation. Default-branch Dependabot alerts
for ring 0.16.20 and curve25519-dalek 4.0.0-rc.3 are absent in PR
lockfile (0.17.14 and 4.1.3 respectively); main remains unmerged.
12 tracked binary integrity checks passed. Full Python suite on
Windows: 61 tests, 1 permission assertion failure, 2 missing PyYAML
errors, 1 skipped; focused new tests passed. Linux CI remains
required. Sing-box build, AAR provenance and current scanner scores
remain open. No main merge or release.


## Phase 3 sing-box and dependency drift gate (2026-11-25)

Both pinned sing-box ARM ABI builds completed twice, same-host hashes
match. Six dependency versions differ from historical binaries; no
promotion. Automated dependency comparison now records drift and
strict mode rejects it. Two new comparison regressions and four
Kotlin downloader tests added. Kotlin download retry budget increased
from four to six attempts, honors bounded numeric Retry-After,
closes retryable HTTP error responses, preserves pinned hashes and
fails on permanent HTTP errors. One previous hosted Kotlin check
failed on HTTP429, another passed; no source finding in failed log.
Full Linux WSL Python suite 67/67 passed (system PyYAML 6.0.3);
Windows-specific permission/PyYAML issues avoided, not suppressed.
12 binary integrity checks passed. Prior hosted APK/iOS builds passed.
Fresh CI, reviewed dependency lock, independent reproducibility,
merged AAR provenance, secure-storage migration and physical-device
acceptance remain open. No main merge or release.


## Phase 3 reconstructed native linked dependency locks (2026-11-25)

Reconstructed both ABI-consistent linked-module snapshots from
bundled engine metadata, verified 22 tun2socks and 81 sing-box
module entries and go.mod checksums, and added strict --locked
candidate build mode. Both engines built for both Android ARM ABIs
with exact linked dependency matches and API24 metadata. Recomputed
all four candidate SHA256 hashes. No replacement of tracked binaries.
Three added regression tests; Linux Python suite 70/70 and 12 binary
checks passed. Previous hosted Kotlin checks both passed after the
retry changes. Other hosted jobs still pending at inspection. Full
optional module archive download blocked by HTTP403; targeted
readonly builds completed. Vulnerability assessment, independent
clean locked rebuilds, AAR provenance, secure-storage migration,
scanner results and device acceptance remain open. No main merge
or release.


## Phase 3 linked Go advisory audit and tun2socks patch candidates (2026-11-25)

Live OSV: 92 historical module versions, 26 module/advisory
matches across 9 packages. Added repeatable informational CI report
with strict CLI option; 4 new unit tests, full Linux Python 74/74
and 12 binary checks passed. Strict live scan rejected findings.
Two tun2socks patch attempts, second resolves all reported linked
module matches: 23 module versions queried, zero matches; both
ARM ABIs pass build, ELF API24 and module verification. Snapshot
inputs/evidence retained; no bundled binary change. Sing-box patch
archive HTTP403, pending. No independent rebuild, stdlib or
reachability assessment, Android device acceptance, or main merge.


## Phase 3 patched sing-box candidate and stdlib follow-up (2026-11-25)

Direct upstream retrieval with sumdb resolved compress v1.20.2
archive blockage. Both patched sing-box ABIs built, API24 ELF
metadata and module verification passed; all 81 linked module
versions returned zero OSV matches (historical 25). Tun2socks
candidate previously zero (23 linked versions). Snapshots saved;
no tracked binary replaced. Separate standard-library query found
23 matches on Go 1.26.5 and 15 on 1.27.0, zero on 1.26.11 and
1.27.4. Upgrade candidate compiler and verify provenance before
independent builds. 12 tracked binary checks passed; previous
hosted native Go report succeeded in reporting mode. No fresh
Python/Flutter tests needed for snapshot-only changes; previous
74 Python and 578 Flutter tests remain last runs. Runtime
acceptance and source provenance for merged AAR still pending.
No main merge or release.


## Phase 3 patched compiler rebuild automation (2026-11-25)

Official Go1.27.4 Windows archive unavailable (404), module zip
blocked (403). Existing compiler unchanged. Strict patched builder
rejects old compiler, snapshot mutation, unexpected dependencies,
findings or incomplete fresh OSV scan including stdlib. Added clean
Linux replica workflow with archive SHA256 pin and independent caches.
75/75 Linux Python tests, 12 tracked binary checks and real negative
compiler gate passed. Hosted clean builds and hash comparison not
yet verified; no new patched binaries claimed. No device acceptance
or main merge/release.


## Phase 3 hosted compiler builds and embedded Go audit (2026-11-25)

Hosted run 45584510998 succeeded on four independent Linux runners
with verified Go1.27.4 and both ARM ABIs, exact patched module
graph and zero fresh OSV version matches including stdlib.
Added independent artifact comparison CLI and CI job; three
regression tests, full Linux Python 78/78 and 12 tracked binary
checks passed. Local artifact retrieval not yet verified; byte
equality remains pending. Embedded AAR version scan 81 queries,
28 advisory matches including 15 stdlib; local sing-box replacement
and bkcores main wrapper source identity unknown. Audit snapshot
recorded, no replacement. Further embedded source recovery,
compatibility/device acceptance and fresh APK security scans open.
No main merge or release.


## Phase 3 independent binary equality and repeatable embedded audit (2026-11-25)

Run 45585302350 comparison job 139106820518 passed all four
patched binary hash pairs. Earlier tun2socks replicas locally
verified; sing-box equality confirmed in hosted job log. New
embedded AAR auditor repeats 81 queries, 28 matches, 4 unresolved
ABI/source entries. Strict mode correctly exits 1; informational
CI upload extended to include report. Source recovery in scoped
locations unsuccessful; corrected unsupported Android libbox version
claim. Full Linux Python suite 81/81, Kotlin quality and 12 binary
checks passed. Hosted audit workflow change awaits CI. No source
reconstruction claim, no production binary replacement, no
physical-device acceptance or release.


## Phase 3 vault recovery and non-destructive migration (2026-11-25)

Disabled Hive automatic crash recovery/truncation and removed
destructive delete/reopen fallback for all config-library boxes.
Accounted for Hive 2.2.3 duplicate opening-future error via a
second same-name waiter. A wrong valid-length key no longer
truncates encrypted files; restoring original key recovers records.
Key persistence is read back before encryption. Overlapping
legacy/encrypted generations fail closed instead of guessing
authority. Partial migration validates existing closed encrypted
boxes before copying other legacy boxes. Flush and close before
deleting a migrated plaintext box. Locked service refuses access
and startup shows a recovery message without starting import or
connection controllers. Four new regressions; 582/582 Flutter
tests passed, targeted analyzer no issues, 12 binary checks passed.
Prior embedded audit hosted job passed. Existing no-keystore
legacy plaintext behavior is retained only when no encrypted data
exists. Recovery of ambiguous overlapping generations requires
manual assistance; recovery screen currently English only. This
is not a secure-storage plugin upgrade or on-device keystore
migration test. Original AAR provenance remains unresolved.
No production binaries replaced or release approved.


## Phase 3 localized storage recovery and plugin migration review (2026-11-25)

Recovery screen now uses the existing English/Persian/Chinese
translation catalogue, device locale and a local language selector
without initializing the normal app services. Scrollable layout,
large text and Persian RTL covered by two widget regressions.
Explicit resetOnError:false preserves the existing plugin behavior.
Full Flutter suite 584/584 passed; touched-file analyzer clean;
12 tracked binary checks passed. Existing wakelock test mock warning
remains. Upstream 10.3.4 is a migration bridge from v9 encrypted
shared preferences; v11 removes the legacy backend. A direct major
upgrade is not justified. See https://pub.dev/packages/flutter_secure_storage/versions/10.3.4/changelog
and https://pub.dev/documentation/flutter_secure_storage/10.3.4/flutter_secure_storage/AndroidOptions/AndroidOptions.html
for migration fixes and default resetOnError:true. Future candidate
must explicitly disable destructive reset, review backup migration
behavior, preserve the existing namespace and key identity, and
verify upgrade on a synthetic v9 vault in an isolated app package
before promotion. Retried dependency resolution in the separate
storage experiment worktree: pub.dev insufficient permissions, exit
69. No dependency or lockfile changed in PR20. Recovery language
selection is session-local and does not access persisted settings.
No physical-device upgrade verified; embedded source recovery and
security scans remain outstanding. No main merge or release.


## Phase 3 isolated secure-storage migration experiment (2026-11-25)

Added hosted dependency-resolution and isolated fixture-build jobs
for flutter_secure_storage 9.2.4 to 10.3.4. Actual app dependency
resolution happens only in a disposable CI checkout. Fixture package
com.blackoutkit.storagefixture uses the real vault code and random
synthetic key, writes one encrypted record on v9 and verifies it
on v10 without creating a replacement. Backup-on and backup-off
variants have identical package/signing identity checked at build
time. Automatic reset disabled. Upstream issue 1289 reports a
backup-enabled legacy migration problem; no settings approved yet.
Local legacy fixture dependency resolution and Dart analysis passed.
Full Linux Python suite 84/84 passed; binary and action-pin checks
12/12 passed. Hosted experiment build and device migration remain
unverified. Main pubspec, lockfile, and runtime vault options unchanged.
No production package installation or release.


## Phase 3 storage experiment dependency and compiler compatibility (2026-11-25)

Hosted run 45588690573 failed both jobs: package_info_plus 5.0.1
requires web <0.5.0 while secure storage 10.3.4 selects web
>=0.5.0, and the generated legacy fixture used Kotlin 1.7.10
with Kotlin 1.9 metadata dependencies. The candidate-only manifest
now pins package_info_plus 8.3.1 (published Dart >=3.3, Flutter
>=3.19, web >=0.5 <2 constraints), and analyzes its actual app
call sites. Fixture-only toolchain pins AGP 8.5.2, Kotlin 2.0.21,
Java 17 and Gradle 8.7 archive SHA256. These versions were
previously tested in the isolated Android toolchain experiment;
not yet verified with secure storage 10.3.4. Two new tests cover
manifest constraints and generated build-tool pins. Linux Python
86/86 and 12 binary integrity/action checks passed. Local upstream
package archive request returned HTTP403; no local v10 build.
No authorized ADB device attached. Main app dependencies,
lockfile, runtime options and tracked native binaries unchanged.
Hosted retry pending; no migration acceptance or release.


## Phase 3 hosted storage fixture builds and automated emulator acceptance (2026-11-25)

Hosted run 45589868510 passed both jobs. App dependency resolution
selected secure-storage 10.3.4, package_info_plus 8.3.1 and web
1.1.1; targeted call-site analysis passed. All three synthetic
APK variants compiled and passed package version/shared signer
checks. Artifact 15010701351 contains fixtures, lockfiles and
SHA256SUMS; local app candidate lock downloaded and inspected.
Added automated emulator acceptance runner: verifies all hashes,
package identities, versions and signer; refuses physical devices
and pre-existing fixtures; validates migration and restart for both
backup settings, removes only its disposable fixture. Hosted API24
and API34 jobs added. Six mock regression tests; Linux Python
92/92 and 12 binary/action-pin checks passed. No real device
acceptance yet, no production dependency, native binary or lockfile
change. Hosted emulator boot and test results still pending.


## Phase 3 scanner evidence coverage checks (2026-11-25)

Hosted APK run 45588690313 completed with ClamAV 1.5.4, zero
infected files and VirusTotal unknown-file for all three APK hashes.
Unknown is not a clean VirusTotal result. MobSF ran on the pinned
image; current detailed findings not independently retrieved yet.
Report generation now checks exact three-file ClamAV coverage,
zero detections/errors, matching VirusTotal filename/hash coverage,
MobSF universal APK digest and severity schema. Scanner status
and counts appear explicitly in evidence; review still required.
Four new regressions, Linux Python 96/96, 12 binary integrity
checks passed; historical locally downloaded scan evidence accepted
by the new validator. No production dependency or binary changed.
Hosted storage migration run 45591441880 was still in progress
at inspection. Actual migration/device acceptance remains open.


## Phase 3 native diagnostic privacy hardening (2026-11-25)

Code review identified libbox raw native callback messages forwarded
to logcat, connection display names and descriptor/port details in
success logs, and raw exception/reason text in several diagnostics.
Removed raw callback forwarding and replaced those logs with fixed
lifecycle messages or exception class names. UI error delivery is
otherwise retained. No native engine or protocol behavior changed.
Ktlint now receives explicit source paths inside android/app/src
and tool/kotlin; generated .cache fixture sources no longer leak
into glob matching. Strict Kotlin quality passed; Android unit
test and lint Gradle tasks passed, Linux Python 96/96, 12 tracked
binary checks passed. Existing Kotlin metadata diagnostic remains
in Gradle output. Newest detailed MobSF artifact download still
unverified; source privacy findings are not a claim that the
scanner's warnings disappeared. Storage emulator jobs still running
at inspection. No production binary replacement or release.


## Phase 3 emulator boot diagnostics and compact scanner evidence (2026-11-25)

Run 45591441880 passed resolution and fixture compilation, but
both API24 and API34 jobs timed out before ADB connected (exit124).
No migration ran and no emulator startup log was preserved.
Extracted CI-only emulator boot runner with explicit acceleration
check, prestarted ADB server, fresh named hardware profile,
SwiftShader software rendering (Vulkan disabled), bounded boot
polling, process liveness check and failure diagnostics upload.
Startup options are a proposed correction, not a confirmed root
cause or verified fix. Reference Android developer emulator docs.
Added compact security summary artifact to APK workflow so reviewers
need not download all APK variants to see attested scan counts and
statuses. Latest completed APK run 45589868521 again reported zero
ClamAV detections and three unknown VirusTotal files. Detailed MobSF
artifact still not retrieved locally. Python 96/96, shell syntax and
12 binary/action checks passed. No production dependencies or
binaries changed; hosted acceptance retry pending.


## Phase 3 emulator runtime dependency repair (2026-11-25)

Hosted retry 45593879636 confirmed both API24/API34 failed in
QEMU dynamic loading: libpulse.so.0 absent, exit127. Resolution
and all three fixture APK builds succeeded. No device migration
executed. CI-only bootstrap now installs libpulse0 from Ubuntu
package repositories before emulator startup, captures preflight
output, prints ldd diagnostics on version-check failure and
uploads both preflight and startup logs. Explicit Linux/GitHub
Actions guard rejects non-CI invocation. Shell syntax, local
non-CI rejection (exit2), Python 96/96 and 12 binary/action
checks passed. Hosted retry still needed to confirm runtime repair.
Production dependencies and native binaries unchanged; no release approval.


## Phase 3 finding-level scanner evidence (2026-11-25)

Compact artifact from run 45593879818 downloaded successfully:
commit f3afdd0, test-only signing, ClamAV 3 scanned/0 infected,
VirusTotal three unknown-file statuses, MobSF 46/100 with 4 high,
10 warning, 1 info, 2 secure and 1 hotspot entries. Report
now includes each finding's severity, title, section, stable rule
SHA256 and full-evidence SHA256, without copying descriptions
that can contain scanner-extracted secrets. Stable rule identity
is based on section/title, not a vendor-assigned advisory ID;
multiple instances may share a rule. Historical full report parsed
all 18 entries successfully. Two new tests cover stable identity,
evidence changes and malformed finding rejection. Python 98/98
and 12 binary/action-pin checks passed. Current loopback-only
cleartext exceptions retained pending runtime acceptance rather
than changing behavior for a score. No score increase claimed.
Storage retry 45595704614 still building at inspection; no
production dependency or native binary changes.


## Phase 3 updater package and private path hardening (2026-11-25)

Require exact nonempty signer-set equality before handing an APK
to the Android installer; partial signer overlap is insufficient.
Only nonempty regular APK files directly in private updates storage
are accepted, with canonical path checks; remove obsolete external
FileProvider mapping. Existing external cached updates must be
redownloaded. Strict release tag parsing permits numeric semver and
legacy beta.N only, with validation at download too. Signer mismatch
message no longer recommends uninstalling the existing app.
Three JVM policy tests and one Dart malformed-tag regression added.
Flutter 585/585 passed; Android unit tests and lint passed;
strict Kotlin checks and 12 binary/action checks passed. Targeted
Dart analysis 5 informational findings, no warnings/errors.
Platform installer confirmation retained; no on-device install or
key-rotation acceptance, no MobSF score improvement claimed.
Hosted storage workflow 45595704614 both fixture builds passed
and emulator jobs were in progress at inspection. No production
binary replacement or main merge.


## Phase 3 updater download integrity and AVD location repair (2026-11-25)

Verified GitHub latest release v1.19.2 supplies SHA256 metadata
for all three APK variants. Updater validates HTTPS official
repository/tag asset URL, requires SHA256 and a 1-256 MiB declared
size, limits progress/cancels oversized responses, stages in a
private temporary directory, verifies exact size and streaming
SHA256 before renaming to the installable path. Existing native
package and signer checks retained; PlatformException reaches
UI without losing the native error code. Three new Dart tests
cover valid digest, same-size corruption, truncation and malformed
metadata. Flutter 588/588, Python 98/98, 12 binary/action checks
and shell syntax passed. Targeted analysis has 3 informational
findings, no warnings/errors. Legacy release assets lacking digest
will now require manual installation. Live download/installer
acceptance not performed; checksum metadata is not independent
signature authentication, and digest verification occurs at download
completion, not on each permission retry.
Hosted storage run 45595704614 confirmed PulseAudio fix and usable
KVM; emulator still failed to locate the created AVD. CI now uses
explicit job-owned ANDROID_USER_HOME, ANDROID_AVD_HOME and AVD
path, checks ini/config existence and emulator listing before boot.
Root cause of path disagreement not yet verified; retry pending.
No production dependency/native binary replacement or main merge.


## Phase 3 cached update verification and recovery safety (2026-11-25)

Every installer attempt now rechecks the actual cached APK size
and SHA256 against the release metadata, including permission
retries; prevents overlapping download/install operations within
the service. On missing/corrupt cached file the settings UI clears
its reference so the next attempt can download again. Native
PlatformException codes preserved. English/Persian/Chinese signer
mismatch recovery now advises preserving installed app and saved
configs, not uninstalling. New mocked channel regression verifies
permission refusal, same-size corruption rejected before installer,
and successful retry after restoring valid bytes. Full Flutter
589/589 passed twice, targeted updater 18/18, 12 binary/action
checks passed. Targeted analyzer before translation edit had
13 existing informational findings across updater/settings/tests,
no errors/warnings. No physical installation tested. Hosted
45596888547 failed one vault regression (584 passed/1 failed)
although local suite passed; investigate before accepting CI.
Storage retry 45597592902 still compiling at inspection.
Production dependencies and native binaries unchanged.


## Phase 3 vault regression cleanup and MobSF high-findings review (2026-11-25)

Hosted APK run 45596888547 failed during synthetic vault test
teardown with PathNotFoundException, after the security assertions.
Inspected installed Hive 2.2.3 source: _openBox catch calls
newBox?.close() without awaiting; backend close deletes its lock
file asynchronously. Test teardown and wrong-key recovery retry
now wait for the isolated fixture lock files to disappear within
5 seconds. Persistent locks still fail; no assertion or production
behavior changed. Local vault suite 9/9 and Flutter full suite
589/589 passed; 12 binary/action checks passed. Linux hosted
confirmation pending. Production failed-open cleanup remains a
separate dependency/lifecycle concern; no runtime workaround claimed.
Downloaded finding-level report from completed run 45596213241:
MobSF 46/100, 4 high, 10 warning, 1 info, 2 secure, 1 hotspot.
High findings: debug signing (test artifacts only; release signing
gate remains); loopback cleartext (requires live traffic acceptance
before tightening); minSDK24 (support policy decision, not silently
raising minimum); CBC/PKCS padding (previous full report attributes
this to secure-storage plugin; isolated migration remains blocked).
No finding waived or marked fixed merely from source inspection.
Storage retry 45597592902 fixture compilation/resolution passed,
emulator jobs still running. No production dependency or native
binary replacement, no main merge or publication.


## Phase 3 storage migration acceptance split (2026-11-25)

Run 45597592902: candidate (backup disabled) passed upgrade and
restart on both API24 and API34 x86_64 emulators. Backup mode
API24 timed out installing the legacy APK; API34 reported fixture
failure without a stage marker. Both emulators booted successfully.
Separate fresh CI emulator per API/mode, bounded 240-second APK
install timeout, stale log reset on disposable emulators, fixed
fixture failure-stage markers without keys/raw exceptions and
harness stage reporting. Mock regression covers isolated backup
mode and failed key-read reporting. Python 98/98 and 12 binary
checks passed. New hosted matrix not yet verified. Candidate
results are synthetic, not real-device production acceptance.
No production dependency or binary replacement.


## Phase 3 verified migration option and full-app experiment (2026-11-25)

Run 45601181502 independently repeated successful non-backup
migration and restart on API24/API34. Backup-enabled mode failed
at read_key on both APIs. Select backup-disabled migration as
the candidate for further validation, with resetOnError=false.
Do not ship backup-enabled mode or suppress its experimental failure.
Full-app APK/iOS build 45601181509 and Tests passed on 46b539b;
Linux vault teardown correction confirmed by hosted build success.
Extended disposable candidate checkout to apply separately tested
AGP8.5.2/Gradle8.7/Kotlin2.0.21 toolchain, resolve storage10.3.4
and compatible package-info, run full Dart analysis/tests and
Android unit/lint/debug assembly. Guarded toolchain transformer
requires exact expected inputs and has regression coverage.
Python 99/99, 12 binary/action checks and diff check passed.
This combined app build remains unverified; no shipping dependency
changes, no installation, no publication. ARM physical acceptance
and interrupted migration recovery remain mandatory review items.


## Phase 3 combined application build and interruption boundary (2026-11-25)

Run 45606227849 full-app candidate dependency/toolchain job
139177667107 passed complete Flutter analysis/tests and Android
unit/lint/debug assembly. Both non-backup emulator tests passed
again; both backup tests failed at read_key. Normal production
APK/iOS build 45606227779 passed. Added synthetic-only gate after
key retrieval but before opening the encrypted box, process
force-stop at that gate, SHA256 comparison of the original
Hive fixture file before upgrade, after interruption and after
restart. This verifies application-boundary interruption, NOT
interruption inside the native plugin migration itself. Mock
coverage rejects modified ciphertext. Python 99/99, 12 binary
checks and local legacy fixture analyzer passed. New emulator
acceptance still pending, ARM real-device acceptance pending.
No production dependency or toolchain changes, no release.


## Phase 3 API24 fixture portability (2026-11-25)

Run 45613036461: full-app combined candidate build passed again;
API34 non-backup passed key-return interruption, restart and
ciphertext comparison. Both API24 jobs failed before migration
when run-as sha256sum exited 243; API34 backup failed at read_key.
Replace shell run-as dependence with fixture-only SHA256 markers
computed after closing the synthetic Hive box, and a flushed
one-time private sentinel at the candidate key-return boundary.
The harness requires valid digest markers for each launch and
compares against the original legacy digest; mismatches fail.
No raw data or key values emitted; no production logging changes.
Mock tests verify mismatch rejection and no run-as calls. Python
99/99, 12 binary/action checks, local legacy fixture analyzer
and diff check passed. Hosted API24 portability not yet verified.
This is post-key-return interruption, not interruption within
the native migration itself. Native replacement/physical device
acceptance remains open. No shipping dependency changes.


## Phase 3 Android toolchain bridge integrated into draft PR (2026-11-25)

Promoted only the three reviewed Android build-file edits from
the independently tested toolchain and successful combined
application experiment (45606227849, 45613036461). AGP 8.5.2,
Gradle 8.7 bin with official SHA256, Kotlin 2.0.21, explicit
BuildConfig generation. Flutter 3.24.0, Java17, min/compile/target
24/34/34, signing, feature flags, dependencies and native artifacts
unchanged. No storage plugin promotion; migration retry 45616889661
still running at inspection. Storage experiment now recognizes
exact promoted pins idempotently and rejects mixed pins before
writing. Private preflight and migration docs updated.
Python 99/99, shell syntax, 12 binary/action checks and diff
check passed. Local offline Gradle failed to resolve AGP8.5.2
plugin artifact, consistent with previous cache blocker; no local
Android test success claimed. Fresh hosted tests/build/security
scans and physical acceptance required. PR remains draft, not
merged or released. Bridge versions are not latest-stack claims.
