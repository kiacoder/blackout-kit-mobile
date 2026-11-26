# MobSF remediation ledger — 2026-11-26

Baseline: published v1.19.3 universal APK, score 50, 3 high / 10 warning /
1 info / 2 secure / 1 hotspot. Candidate commit 567e74f, build 45823597770,
has a hash-bound completed MobSF report (SHA256
2b8f32e758ccfa07735e277eaf2e44c0a6be86f3892facc05804eeea02619e07).
The candidate score is still 50: the loopback cleartext finding is absent,
but debug signing adds a test-only high finding. ClamAV scanned three APKs
without a detection. VirusTotal is not configured on that branch. These are
not guarantees of security or production device acceptance.

| Finding | Disposition / evidence still required |
| --- | --- |
| Loopback cleartext | Removed in 567e74f; fresh MobSF report confirms absence. Raw SOCKS is unaffected by the HTTP policy in principle; device acceptance pending. |
| Debug signing (candidate only) | Expected test artifact; production requires pinned release certificate. Do not treat as fixed on candidate or alter signing checks. |
| minSdk24 | Real OS support/patch exposure, not a demonstrated app exploit. Retain compatibility pending maintainer support-policy decision; raising to 29 does not guarantee a patched OS. |
| CBC/PKCS7 | Open. Actual cached v9.2.4 source uses AES256-SIV/GCM for normal ESP, but contains CBC fallback and switches to legacy storage on ESP initialization failure. Do not label unreachable or safe. |
| System CA trust | Design review: system CA/hostname verification, no redirects, no user roots or custom trust overrides. Arbitrary destinations and independently managed endpoints cannot use a durable app-owned pin set. Residual CA compromise risk remains. |
| ProfileInstallReceiver | Review: AndroidX tooling receiver requires platform DUMP (signature/privileged/development), not a normal runtime permission. Verify exact merged manifest; retain tooling unless there is a separate requirement to remove it. |
| Temp file | Shared document import no longer creates a cache file (29b907b). Bounded strict UTF-8, URI grant validation and 6/6 JVM tests. Native engine private config lifecycle and third-party cache paths remain review items. |
| External storage | Candidate pins file_picker 8.1.7 and package_info_plus 8.3.1 using exact successful experiment lock (45771214111); permission gate checks every APK. The plugin can still legitimately access a user-selected document. Fresh builds, dependency review and physical picker test remain required. |
| Insecure RNG | App key paths use SecureRandom; obfuscated dependency classes still require exact mapping and usage review. |
| Raw SQL | Obfuscated dependency classes require source mapping, parameter-binding and reachability review. No automatic false-positive designation. |
| SHA-1 | Determine use from mapped source (identifier/cache vs security decision); not automatically safe. |
| IP disclosure | Native Rust endpoint diagnostics reduced; distinguish fixed loopback/documentation addresses from actual sensitive values. Review mapped classes and runtime logs. |
| Hardcoded credentials | Map flagged fields to source; synthetic or public constants need explicit evidence, actual credentials must be removed/rotated. |
| Heuristic secrets | Review exact findings securely, do not paste raw strings into docs/logs. Many appear to be compiled symbols; that observation is not full clearance. |
| Logging | Fixed known application diagnostics; review dependency logging and real runtime redaction. |
| Permission hotspot | Review camera (QR), notifications (VPN/update), install packages (user-confirmed updater), app query (split tunneling); verify actual merged permission set and necessity. |

## Encryption migration gate

The production dependency remains flutter_secure_storage 9.2.4. The v10.3.4
candidate and the backup-patched synthetic fixture passed six jobs in
45807853144, including API24/API34 upgrade/restart/interruption tests.
This proves the specified synthetic scenario only. The interruption rendezvous
is after the migrated key is returned, not inside each migration write.
Upstream issue #1293 reports a markerless ESP migration failure with backups.
The local backup patch is fixture-only; do not ship it unreviewed.
v11 removes legacy algorithms/ESP, requires prior v10 migration and raises
compileSdk to 37. A direct upgrade from v9 may strand existing user data.
Existing Hive box encryption/integrity is a separate vault review; changing
the keystore dependency alone does not resolve all at-rest integrity risks.
No reset-on-error or key deletion is permitted as remediation.

## Evidence and promotion

No scanner suppression, security gate bypass, signing change or production
release is authorized by this ledger. The file-picker candidate lock SHA256
is ba024cb8e191da315211c12a9f3f39adafc74d71b8b59f31323e1308d0b2d246.
Only the reviewed resolver changes are staged; full dependency scanning is
pending. Local Windows pub cache lacks the new file-picker package; offline
resolution cannot establish candidate success. The previous CodeQL Java/Kotlin
job 45823603385 failed to resolve Kotlin Gradle plugin 2.4.21, despite normal
build/quality checks passing; rerun against the current candidate rather than
suppress analysis. New review artifact collects exact report and available
R8 mapping without publishing mapping as a release asset. Match the universal
APK hash and build identity before using mapped evidence.

References:
- https://github.com/juliansteenbakker/flutter_secure_storage/issues/1293
- https://pub.dev/packages/flutter_secure_storage/changelog
- https://pub.dev/packages/file_picker/changelog
- https://developer.android.com/reference/androidx/profileinstaller/ProfileInstallReceiver
- https://android.googlesource.com/platform/frameworks/base/+/android12-release/core/res/AndroidManifest.xml
- https://developer.android.com/privacy-and-security/security-ssl
- https://docs.flutter.dev/reference/security-false-positives

Phase 2 remains open until the fresh candidate scan is reviewed, actual
vulnerabilities are fixed, security-relevant residual risks are accepted by
the maintainer, migration and physical-device gates pass, and the exact
production-signed APK is rescanned. Do not equate zero scanner warnings with
security.

## Fail-closed storage policy

Removed the intentional plaintext fallback from ConfigService and SecureVault.
If the platform key cannot be read, created and confirmed, the app enters its
existing recovery screen rather than opening or creating plaintext boxes.
Existing legacy/encrypted files remain untouched; the user can restart after
restoring keystore access. This deliberately changes availability on devices
without functioning secure storage. The tests now explicitly inject a memory
key store for synthetic data rather than relying on the old production
fallback. Added fresh-install failure/recovery coverage and revised legacy
preservation assertions. Local 609/609 Flutter tests passed with cached
pre-picker dependencies (no-pub); full locked candidate verification remains
required in hosted CI. This fixes the plaintext application fallback, not the
separate CBC path inside flutter_secure_storage or Hive's at-rest integrity.
