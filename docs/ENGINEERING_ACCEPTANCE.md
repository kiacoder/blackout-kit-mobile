# Engineering hardening — acceptance criteria (2026-11-26)

Baseline: main 81e613a, published v1.19.3, v1.19.4 candidate on main.
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
