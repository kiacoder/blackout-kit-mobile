# Release security policy and verification

Android release signing already exists. The public certificate was extracted
from the published v1.19.2 ARMv7 APK after checking the GitHub asset digest:

- APK SHA-256: 77ca8bb0ddc1b96d7f08226325ec35658767e662d3272c71779287d462e2684f
- Certificate SHA-256: 248aead09395c86d27f71bff4ce55283b2acb961d4c83c75442ea2e8cc29484a
- GitHub Actions variable ANDROID_RELEASE_CERT_SHA256 pins this identity.
- The four existing ANDROID_KEYSTORE_* secrets are retained; no keys are rotated.

## CI policy

The Build APK workflow runs on the experimental PR branch and on release tags.
Branch artifacts are test-only, debug-signed, and never use Android release
signing secrets. They are not the local native-test APK: production build
variants intentionally exclude experimental WG/AWG JNI libraries. Tagged builds
must match pubspec version and a commit reachable from main, must have the
existing release signing credentials, and must match the pinned certificate.

The build gates include Flutter analyze/tests, Android JVM tests, locked Rust
tests/build, apksigner validation, exact three APK variants, ABI/native-library
inventory, refreshed ClamAV signatures and successful malware scan, SPDX
repository SBOM, SHA256SUMS, and GitHub build provenance attestations for
APKs and JSON evidence. Native hashes cover actual packaged libraries; the
repository SBOM is not an exhaustive inventory of opaque native dependencies.
CodeQL, Dependabot and secret scanning remain separate security checks.

Tagged runs stage a draft only after both platform builds and artifact checks
succeed. The publishing job verifies the exact source commit and workflow
attestations. Existing releases are never overwritten. Review security findings,
MobSF/VT reports and device acceptance before manually publishing the draft.
Do not enable GitHub immutable releases until this workflow is merged to main:
the current main workflow attaches the iOS asset after initial publication.
After merge, enable Settings > General > Releases > Enable release immutability.
The signed iOS workflow is independent and requires Apple signing credentials.

## Optional scanners

- Set repository variable MOBSF_IMAGE to a reviewed official
  opensecurity/mobile-security-framework-mobsf@sha256:<digest> to run its local
  container static analysis of the universal APK. The container is only bound
  to loopback and disables its VirusTotal upload option. Review its report;
  it is not an automatic finding-free verdict. Missing variable is recorded.
- Set repository secret VIRUSTOTAL_API_KEY for hash-only lookup of tagged
  APKs. No binary is sent to VirusTotal. New files may be unknown; use the
  report links to manually submit approved public binaries if desired.
  Review results and false positives before publishing. Missing key, unknown
  file or API error are explicitly recorded, not interpreted as clean.
- ClamAV is an automated local antivirus gate; no APK bytes are transmitted
  to an external scanner. Antivirus, static analysis and provenance do not
  establish that an APK is free of malware.

## User verification

Download an APK and the checksum file from the same release. Verify:

    sha256sum -c SHA256SUMS.txt
    gh attestation verify APK_NAME.apk --repo kiacoder/blackout-kit-mobile --signer-workflow kiacoder/blackout-kit-mobile/.github/workflows/build.yml
    apksigner verify --verbose --print-certs APK_NAME.apk

Compare the SHA-256 signing certificate with the fingerprint above. GitHub
attestation proves origin, not absence of malware. Android signing identity
is distinct from Google's Play Protect certification.

## References

https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
https://docs.virustotal.com/reference/file-info
https://github.com/MobSF/docs/blob/master/configurations.md

## CI repair: first security pipeline run (2026-11-24)

Run 45362611848 compiled Android and iOS successfully but failed after
compilation: certificate-report parsing and a branch-name/commit-label
mismatch in the IPA size check. Pin Android build-tools 36.0.0, validate
the reported signer count and leaf fingerprint (including numbered leaf
format), and use one filename label throughout IPA packaging. The historical
v1.19.2 ARMv7 certificate was verified again with the pinned tool.

CodeQL alert 27 concerned a disposable loopback Mihomo test controller
credential in a named config file. The Linux fixture now passes an anonymous
memory-backed descriptor to the child process. A Linux regression checks
descriptor permissions and child readability; the full external Mihomo
binary suite has not been rerun in this repair.

CodeQL alert 36 concerns missing certificate pinning on arbitrary user-defined
HTTPS website probes, not a trust-all TLS implementation. Probes now explicitly
require HTTPS, validate hostname syntax and retain Android system CA and
hostname validation, without redirects or trust overrides. The Android base
network policy explicitly denies remote cleartext and trusts system roots.
A fixed application pin set cannot represent arbitrary user destinations;
Android's own documentation cautions against certificate pinning:
https://developer.android.com/privacy-and-security/security-ssl
Keep this finding visible for review if CodeQL continues to report it.
No CodeQL rules, malware gates or signing verification have been disabled.

Local verification: 575 Flutter tests, 11 focused Python security/staging
tests, Linux anonymous descriptor regression, actionlint, and historical
certificate verification passed. GitHub rerun remains necessary.


## Scanner configuration and dependency remediation (2026-11-24)

The repository secret VIRUSTOTAL_API_KEY now exists (only its name was
inspected). Hash-only GET lookups are enabled for the maintainer integration
branch, main and release tags. Unknown files, missing reports and API errors
are not clean verdicts. Never publish the key, send it to MobSF or upload
unapproved APKs to VirusTotal. VirusTotal public API terms prohibit use in
commercial products/services; verify the applicable entitlement before use.

MOBSF_IMAGE is configured to the official MobSF v4.6.9 multi-platform image:
opensecurity/mobile-security-framework-mobsf@sha256:14646df326970ba21558c3c67e0a4ab9e9d92f7938ecb7b1a780c8cc536e16b0
Source: upstream successful release build
https://github.com/MobSF/Mobile-Security-Framework-MobSF/actions/runs/44358831543
(the manifest list push for v4.6.9). The laptop's Docker registry returned
HTTP 403, so the first actual container scan must run on GitHub. Both MD5
and SHA-256 must match the universal APK before accepting its report.

Dependabot #1 and #2 originate in boringtun 0.6.0, which pulled ring 0.16.20
and pre-release curve25519-dalek 4.0.0-rc.3. Updated boringtun to 0.7.1,
ring to 0.17.14 and resolved curve25519-dalek 4.1.3. Cargo tree confirms
only the patched versions in the resolved graph. Host Rust tests: 13/13.
Native WG/AWG acceptance is still a separate Android gate. Dependabot
default-branch alerts cannot be considered closed until main is updated.

CodeQL #40 (medium, certificate pinning): the public website reachability
probe accepts user-selected destinations, sends no application credentials,
uses HTTPS, validates hostnames and Android system trust, and disables
redirects. Android documentation recommends against fixed certificate
pinning; no static set can cover arbitrary websites. This is a documented
review finding, not an implemented pinning fix. No alert has been dismissed.
Quality notes: clarify IP-mask arithmetic (#38); remove unreachable
pre-API24 stopForeground fallback (#37); use the modern package UID overload
on API33+ (#26), preserving the supported API24-32 compatibility overload.
The getAllNetworks synchronous enumeration (#25) is a deprecated compatibility
API, not a reported security vulnerability. Replacing it with a callback
registry changes lifecycle semantics and requires device testing.

Review actual MobSF and VirusTotal evidence and CodeQL after the new CI run.
Do not merge before actionable findings are resolved and remaining risks
are reviewed. No release is approved by this entry.

## Post-v1.19.3 CodeQL remediation (2026-11-26)

Reviewed the ten open main-branch alerts #42–51. #44 (arbitrary APK
installation): native installer now accepts a validated release tag instead
of a caller-controlled path, derives the private archive filename, checks
bounded exact size and SHA-256 independently of Dart, checks the archive
package and requested version, and retains exact nonempty installed signer
matching plus Android's user-confirmed installer. Hashing and package
inspection run on the channel's serial background queue; the installer UI
runs on main. The digest metadata is supplied by the official-release Dart
flow, not an independent publisher signature; the installed signer remains
the independent trust boundary. No claim that this eliminates every file
mutation race or that CodeQL will recognize the guards. No alerts dismissed.

#51 reuses a lazily created SecureRandom for the XUDP key; #47 uses
ContentProviderClient.close() (API 24+); #49/#50 use the API 33+ typed
PackageInfoFlags overload with necessary API 24–32 fallback. #46 and #48
likewise have existing older-API compatibility branches. #45 is synchronous
network enumeration, whose callback replacement requires lifecycle/device
verification. #42/#43 retain normal HTTPS system trust and hostname checks
without trust overrides; arbitrary website targets cannot use a fixed pin
set, and the diagnostic endpoints require certificate-rotation planning
before optional pins. No change to minSdk or intentional TLS policy.

Verification: 605 Flutter tests, analyzer 0 warnings/errors (196 infos),
ktlint/Detekt, 12 integrity checks; direct Kotlin 1.9.25 compile of UpdatePlugin
and its test with Android API 34, actual Flutter engine jar and AndroidX
core 1.13.1, then JUnit 5/5. Full local Gradle blocked by missing offline
AGP 8.5.2 resolution; hosted Android build/lint, fresh CodeQL and device
update acceptance required. Published v1.19.3 unchanged.

### Diagnostic endpoint follow-up
For #43, Android SOCKS IP diagnostics now accept only exact HTTPS URLs
for api.ipify.org and ipwho.is, reject bodies above 32 Ki characters,
ignore caller-supplied SOCKS ports in favor of the live session, and
return no geo lookup result when the tunnel session changes. Tests cover
endpoint rejection and the exact response-size boundary (JUnit 2/2);
ktlint, Detekt and 12 integrity checks pass. Standard TLS certificate
and hostname validation is unchanged. This reduces the diagnostic
surface, but does not implement certificate pinning or close #43 by
itself. Fresh Android CI and device testing remain required.

### PackageInstaller migration candidate (#44)

Replace the ACTION_VIEW APK intent and update-specific FileProvider with a
PackageInstaller.Session owned by the app. Preserve private release-tag path
confinement, bounded size/digest checks, exact package/version name and exact
nonempty signer matching; reject non-increasing Android version codes.
Stream the APK to base.apk while independently checking the exact byte count
and SHA-256, fsync and commit only on success; abandon a failed staging session.
On API 31+ require user action explicitly. Older Android versions retain the
normal REQUEST_INSTALL_PACKAGES consent flow. The explicit status PendingIntent
is mutable solely for platform status extras and targets a non-exported
receiver with a session-specific action/data check. Pending confirmation is
resolved to a system activity. A method-channel success means submission,
not completed installation. Terminal callbacks show the platform outcome.

Local verification: ktlint/Detekt passed, 12 inventory checks, compilation of
installer sources using Kotlin 1.9.25, Android API 34, actual Flutter engine
and AndroidX 1.13.1 jars; JUnit 9/9 (archive path/signers, streamed exact bytes,
truncation, oversize, digest tamper, invalid metadata, equal/older version).
No device connected via ADB. Keep candidate unmerged until Android acceptance
covers real signed update, wrong package/signer, tamper, cancellation, restart,
unknown-source permission denial/retry, API 24/31/34+, and OEM confirmation UI.
The asynchronous confirmation can be subject to background-activity launch
restrictions; an interrupted or orphaned session needs a tested recovery path.
Verify split versus universal version-code selection before promotion. A
successful CodeQL scan is not proof of functional installation. No alert
dismissal or published release change.

References: https://developer.android.com/reference/android/content/pm/PackageInstaller.Session
and https://codeql.github.com/codeql-query-help/java/java-android-arbitrary-apk-installation/.
