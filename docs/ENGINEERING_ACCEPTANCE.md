# Engineering hardening — acceptance criteria (2026-11-26)

Baseline: main 81e613a, published v1.19.3, v1.19.4 candidate with additional PR #27 hardening.
Do not claim production acceptance from static analysis, a host test, or compilation alone.

| Workstream | Required evidence |
| --- | --- |
| MobSF | Fresh universal APK hash-bound report; disposition each finding, with source/dependency mapping and regression evidence. No hidden suppressions. |
| Vault | Signed synthetic upgrade fixtures, crash/interruption and wrong-key recovery, backup restore, physical API/OEM coverage. No reset-on-error or deletion of old data before verified migration. |
| Controller | Extract capability, scan, session lifecycle, recovery and identity services; retain public GetX behavior; full regression suite after each extraction. |
| Rust | Complete fail-closed protocol dialers, TUN IPv4/IPv6, DNS, protected sockets, bounded flow lifetime, cancellation and interoperability; no direct fallback or production capability claim before real device traffic passes. |
| Device | Authorized disposable test devices; Wi-Fi/cellular handover, offline/recovery, app background/process death, revoke, permission denial, kill switch, IPv4/IPv6 and DNS leak checks. |
| Reproducibility | Same commit and exact toolchain, two independently provisioned workers; compare unsigned payloads and exact bytes separately; record native artifact provenance and lockfiles. |
| Performance | Repeat matched idle and active runs with battery, throughput, RAM/PSS, CPU, latency and device/OS/thermal context. Use synthetic traffic and report variance. |
| Documentation | Current status linked to immutable release/CI evidence and explicit limitations. Historical research is not current support. |
| Independent review | Third-party reviewer, scoped threat model, reproducible evidence, remediation/retest report. Internal review is not independent. |

## MobSF baseline — v1.19.3

Report: 50/100, 3 high, 10 warning, 1 info. Do not infer new-release findings from old obfuscated names.

- High loopback cleartext: constrain to loopback, inventory HTTP and SOCKS callers, test removal in a candidate. Localhost exceptions are not remote HTTP permissions.
- High API24: document OS patch-level exposure and assess compatibility before raising minSdk. Do not break existing devices silently.
- High CBC in flutter_secure_storage: candidate v10 storage migration exists separately; requires preserved key/data across interrupted and markerless backup recovery. Do not switch dependency until full acceptance.
- System CA trust: preserve normal certificate and hostname checks. User-selected destinations and independent public diagnostic services cannot safely have static developer-controlled pins.
- ProfileInstallReceiver: validate actual DUMP permission and exported component necessity against merged manifest.
- Temporary files/external storage: verify private ownership, cleanup and permission-free file picker candidate; review data lifetime.
- Random, raw SQL, SHA-1, hardcoded-secret and IP disclosure reports: map exact compiled class to source/library; distinguish non-cryptographic and synthetic values from actual security defects. Redact endpoint diagnostics. Review logging, permissions and secrets without publishing raw scanner strings.
- Retain all scanner and supply-chain gates. Repeat MobSF on the actual signed release.

## Initial branch changes

Extract engine capability policy with reactive inventory preserved; add focused test. Redact Rust endpoint logging and misleading transport-success text. Add byte/ZIP-payload comparator; equal payloads do not establish identical APKs. All further gates remain open until evidenced. No dependency change in this increment.

## Loopback policy candidate

Source review found raw loopback SOCKS readiness and HTTPS-over-SOCKS calls,
not a current app-side HTTP URL targeting localhost. Remove the Android HTTP
cleartext exception, while preserving the engine's raw local socket transport.
Native engine traffic is outside the Android HTTP network policy. The previous
structural test now requires zero cleartext exceptions. A fresh APK/MobSF scan
and Android device checks (Xray, sing-box, site probes and exit-IP lookup) are
required before promoting this change. Keep this candidate on the hardening
branch; no minSdk or storage dependency change in this increment.

## Reproducibility and physical measurements

Android release and Rust cross-check workflows now use the existing quality
compiler pin (1.99.1), not a floating stable Rust release. Cargo manifests,
Cargo.lock, Flutter dependencies and action SHAs are unchanged. This does not
make the complete APK reproducible: NDK, JDK patch, SDK/runner images, signing
and ZIP metadata still require controlled independent-build evidence.
Run tool/apk_compare.py on two equivalent APKs; only exact byte matches pass.

For an authorized lab device, select the serial explicitly and use
`python tool/device_metrics.py --serial TEST_DEVICE --scenario idle` (then
repeat under matched connected and recovery workloads). The tool reads PSS,
package CPU samples and coarse whole-device battery fields without emitting
raw dumps, serials or network addresses. Missing readings remain null. It does
not modify the device, generate traffic, measure energy, or establish a
throughput result. Record device model/OS, temperature, power state, screen
state and test duration separately. For throughput, use a controlled lab
endpoint and a known synthetic payload, compare bytes / elapsed time with
and without VPN, repeat and report variance. Never use production user data.

Physical acceptance sequence: fresh install; save synthetic configs; restart;
upgrade with the same signer; verify configs and preferences; interrupt only
on disposable fixtures; verify recovery without deleting prior data; then
exercise offline/reconnect, Wi-Fi/mobile handover, screen lock, revoke,
process death, DNS and IPv6 policy. Observe kill-switch behavior from an
independent controlled endpoint. No device was attached at this checkpoint.

External audit evidence package: source commit, release APK hashes, pinned
signer certificate, SBOM and native component inventory, threat model,
full scanner reports, known exceptions, migration evidence, independent
build results, physical/network failure matrix and benchmark methodology.
A named external reviewer must validate and retest the findings; this document
is preparation, not an audit certificate.

## PR #27 follow-up ? 2026-11-26

Local pinned Flutter 3.24.0/Dart 3.5 toolchain: exact lockfile resolved,
strict analyzer zero diagnostics, 618 Dart tests passed. Kotlin quality
and tracked-binary/action-pin checks passed locally. The dependency
change replaces the incompatible wakelock_plus 1.1.4 constraint with
1.3.2, preserving package_info_plus 8.3.1 and declaring ffi/path_provider
directly. All other resolved package versions remain unchanged.

Java setup v5 replaces v4 at a fixed commit. Android exit-IP parsing now
uses numeric-only validation. Remaining version notices are not proof of
vulnerabilities: Flutter SDK constraints, mobile_scanner RenderScript,
older workflow actions, Gradle plugin warnings and secure-storage CBC
need separate compatible upgrades and regression evidence. A broad upgrade
or warning suppression is not an acceptance substitute.

The preceding CodeQL Kotlin scan failed during dependency resolution;
the rerun completed successfully. All hosted checks must be repeated on the final
head. No physical device was attached. No merge or release approval is
implied by this checkpoint.

### Follow-up: native cleanup

The prior PR head 6c6b5a3 reached 40 successful hosted checks with no
reported failures, but 12 remained in progress at inspection. This follow-up
adds path-boundary hardening and removes two native compiler warnings.
Ten local focused JVM tests passed with -Werror. The revised head requires
fresh hosted checks; physical device, scanner upgrade and authenticated
vault migration gates remain open. See MOBSF_REMEDIATION.md for details.

### Follow-up: subprocess shutdown and procfs race

On a8f0ba7 the native launcher lifecycle job (run 45876422267) failed
because a process disappeared between opening and reading /proc/PID/stat.
The test now accepts only ENOENT or ESRCH as disappearance, or an observed
zombie. Permission errors and a live process past the deadline still fail.
The deterministic regression and all seven supervisor tests passed under
Ubuntu WSL, including ten consecutive repetitions.

SubprocessLifecycle now clears/restores the caller interrupt around the
bounded cleanup and attempts an exit check even after interrupted waiting
and escalation. Two new JVM regressions cover the final exit check and
interrupt preservation on cleanup failure. All 23 focused JVM tests passed
with -Werror; strict Kotlin static quality also passed.

No production supervisor activation, orphan deletion, cipher migration,
or device acceptance is claimed. Production ProcessBuilder readers do
not yet have the experimental lifetime-pipe guarantee; sweeping session
files after app restart could delete a file still needed by a live reader.

### Follow-up: vault preflight

All 24 focused vault tests, all 621 Dart regression tests and strict Dart analysis passed locally.
New tests prove that an incompatible later legacy box preserves both
original files, incompatible existing encrypted records block legacy
deletion, and key loss during initialization refuses writes and allows
recovery with the original key. No encryption format or dependency change.
See MOBSF_REMEDIATION.md for scope and remaining risks.

### Follow-up: authenticated record prototype

Isolated development-only AES-256-GCM envelope added; seven focused
tests, all 628 Dart tests, strict Dart analysis and supply-chain inventory passed. Exact lockfile resolution passed
with cryptography 2.9.0 added only as a development dependency. No
existing package version, production storage format or key slot changed.
See VAULT_V3_EXPERIMENT.md for the format, recovery gates and limitations.
This is not production migration approval.

### Follow-up: generation authentication and recovery classification

Eight additional development-only tests verify the authenticated manifest,
exact-manifest commit marker and fail-closed recovery classification.
The record and generation suites passed all 15 tests; the complete Dart suite
passed all 636 tests, strict Dart analysis and supply-chain inventory passed. No production code or dependency versions changed. Whole-generation
rollback, durable filesystem transactions, platform key management and
on-device migration remain unverified. See VAULT_V3_EXPERIMENT.md.

### Release documentation reconciliation

The release guide now matches the tag-to-draft workflow, existing pinned
signer, exact artifact verification and manual publication policy. Current
status, test and Android guides distinguish the November 16 historical
evidence from the current candidate. iOS build artifacts are explicitly
unsigned; DNS routing does not establish leak-proof operation. The
shipping vault remains CBC, and dependency popularity is not a security
verdict. Relative Markdown link targets were checked across all 48 tracked
Markdown files; no missing file targets found (external URLs and anchors
not validated). CodeQL alerts 42 and 43 remain open and visible; see
RELEASE_SECURITY.md for rationale. No physical device acceptance or final
release approval is claimed.

### Final CI deprecation and security review (2026-11-27)

At 860fad3, hosted checks reported 40 successes, five skips and zero failures.
The Android log reported Node 20 action runtime deprecations, mobile_scanner
4.0.1 RenderScript deprecations, an Espresso manifest warning and Gradle
9 compatibility notices. Upgrade checkout to v5.0.0, upload-artifact to v6.0.0
and download-artifact to v7.0.0 at verified upstream commit SHAs; all three
manifests declare node24. These are runtime-transition versions, not claims
of newest releases. The artifact actions include upstream punycode fixes.
No signing, scanner, permission, artifact path or publishing gate changed.
Fresh hosted checks must establish upload/download and build compatibility.
Scanner camera, Gradle and SDK upgrades remain separate compatibility work;
no warning suppression or claim of zero build warnings.

Rechecked open CodeQL #42/#43 against the final Kotlin source: HTTPS,
no redirect following, and system-only Android trust with cleartext denied.
Keep both alerts open; fixed pins are not appropriate for arbitrary or
independently managed endpoints without an operational rotation plan.
The residual CA compromise risk, legacy CBC, supported old Android versions,
and interrupted engine-file lifecycle remain documented risks. ADB reported
no attached devices; physical migration, VPN and updater acceptance remain
unverified. The release must remain unpublished until the exact production
APK and device gates are satisfied. See RELEASE_SECURITY.md and
MOBSF_REMEDIATION.md.
