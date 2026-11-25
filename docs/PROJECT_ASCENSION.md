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
