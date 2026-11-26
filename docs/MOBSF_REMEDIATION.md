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

## Candidate scan and mapping follow-up (6be157b)

Build 45826558797 Android job succeeded; Tests 45826567611 succeeded with
the exact upgraded file-picker lockfile. Its MobSF score is 51/100, 3 high,
9 warning, 1 info, 2 secure, 1 hotspot. The SHA-1 warning is absent and the
permission hotspot count dropped from four to three. The debug signing
finding is candidate-only. The APK storage-permission gate passed; the
external-storage code warning nevertheless remains. No scanner suppression.

R8 mapping from that exact run identifies the following classes:

| Rule | Mapped ownership | Disposition |
| --- | --- | --- |
| android_read_write_external | FilePickerDelegate, FileUtils | Broad permissions removed; provider-scoped selection and cache-copy code remains. |
| android_temp_file | TransientEngineConfig, FileUtils | Shared-import MainActivity finding absent; engine file lifetime and picker cleanup still matter. |
| android_hardcoded | NativeTunnelConfig | Source constructs UAPI private_key/public_key/preshared_key fields from supplied configuration, not an embedded secret in those expressions. Exact flagged statement still requires confirmation. |
| android_insecure_random | kotlin.random.AbstractPlatformRandom, FallbackThreadLocalRandom, PlatformThreadLocalRandom | Standard library PRNG classes; app native key generation uses SecureRandom. Dependency callers still require reachability review. |
| android_ip_disclosure | BlackoutVpnService, EngineRunner, VpnPlugin, ProbeEngineController, SiteProbeRunner | Review fixed addresses and runtime diagnostic fields separately; class names alone do not establish leakage. |
| cbc_padding_oracle | fluttersecurestorage.ciphers.StorageCipher18Implementation | Confirmed legacy dependency code; migration remains open. |
| android_sql_raw_query | Google DataTransport SQLiteEventStore, SchemaManager and synthetic Lambda | Dependency ownership established, not proof of SQL injection or absence thereof. Review exact SQL and input binding. |

No raw secret candidates are copied into the ledger. Mapping identifies code
ownership but is not a dynamic reachability or exploitability proof.

## Migration durability and file picker follow-up

Before legacy box deletion, reopen the encrypted copy and compare nested
records, then re-read and compare the original persisted vault key. A failed
readback or disappearing key preserves the legacy and encrypted generations.
This hardens Hive migration, not the upstream secure-storage algorithm switch.
Picker requests a stream (no whole-document bytes), enforces the actual
5 MiB limit, strictly decodes UTF-8, and attempts plugin-owned cache cleanup
in finally after success, cancellation or failure. Cleanup is single-flight
across import screens; failures are logged generically without paths or
credentials. The plugin may still copy provider documents before Dart reads;
physical Android/iOS picker checks and the next APK scan remain required.
Local Flutter tests: 614/614 (cached dependencies); focused vault: 18/18.
Latest hosted regression tests on 33e4f53 (45827658258) passed with the
reviewed lockfile. Independent physical-device acceptance remains open.

## Migration matrix follow-up

Run 45826558705: full-app candidate compile and fixture compile passed;
API 24 candidate/backup and API 34 candidate passed. API 34 backup failed
at legacy-launch before candidate installation; cause not established. Do
not record that case as passed or as an encryption failure. Require user-0
unlock/credential-storage readiness and package-manager readiness on the
fresh emulator, with a bounded deadline and explicit launch status on failure.
Extend the post-key interruption gate to both backup and non-backup paths,
retain SHA-256 verification of the unchanged encrypted library, and rerun
fixtures whenever secure_vault.dart changes. This remains a synthetic test,
not an interruption inside the upstream native migration transaction. No
production storage dependency or scanner configuration changed.

## Shared document admission and old cache cleanup

Android content-provider reads now execute on a serial Flutter background
TaskQueue, not the activity thread. The pending payload uses an atomic take;
URI admission requires content scheme, a resolvable external provider UID
and an actual URI-specific read grant at consumption time. Providers accessed
only through broad permissions, same-UID providers and cross-user authorities
are refused. API 33+ uses typed provider-resolution flags; the deprecated
integer overload remains solely for API 24–32 compatibility. The 5 MiB
stream bound and strict UTF-8 remain. This is not a time-bound provider read:
a stalled provider can still delay the import queue. Physical share/open-with
and warm/cold-start compatibility need verification, including revoked grants.
During normal Dart intent polling, cleanup attempts only numeric import-*.cfg
regular files at the top level of the app-private cache, matching obsolete
copies generated by the previous importer; no recursion or external provider
path deletion. It does not promise secure erasure of flash storage. Recovery
mode does not poll this channel. Seven isolated JVM import tests passed;
615 local Flutter tests passed before adding the cache helper, and strict
Kotlin checks passed afterward. A source guard is not an Android permission
integration test. No production dependency changes in this increment.

Scan 45829828751 on 23a6461: Android/iOS builds passed, MobSF remains 51/100
(debug-signed candidate, 3 high/9 warning), and the storage-permission gate
passed. Remaining CBC and minSdk findings are unchanged. Upstream v11.2.0
requires Dart >=3.8 while this app pins Flutter 3.24.0 (Dart 3.5). Note that
v11.1 changed the original v11.0 compileSdk pin to flutter.compileSdkVersion
(36 at that release); do not infer current toolchain compatibility from the
older v11.0 pin. A direct v9-to-v11 upgrade remains unsafe for legacy stores;
any future toolchain experiment must also address users skipping releases.
Sources: https://pub.dev/packages/flutter_secure_storage/changelog ;
https://github.com/juliansteenbakker/flutter_secure_storage/blob/develop/flutter_secure_storage/pubspec.yaml ;
https://developer.android.com/reference/android/content/Context#checkUriPermission(android.net.Uri,int,int,int) ;
https://docs.flutter.dev/platform-integration/platform-channels .

## CI failure follow-up

Run 45832122237: both API34 modes passed including interruption and restart.
Both API24 jobs stopped before fixture installation because the readiness
probe did not recognize the older image's user-state output. Android 7
UserController.dump and UserState.dump in AOSP android-7.0.0_r1 emit
"User #0: state=RUNNING_UNLOCKED" in the full activity dump. Use that dump
as the API24 fallback, and require a positive package-manager path. Keep the
bounded readiness deadline and all original fixture checks. This is a
candidate infrastructure fix until the next emulator matrix passes.
Standalone iOS run 45833521156 was cancelled before runner acquisition;
GitHub check annotations report macOS arm64 capacity constraints. Combined
build 45833509159 passed both Android and iOS for f976da8. Do not weaken or
remove the standalone check in response to runner capacity.
