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
