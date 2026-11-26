# Deployment and release guide

Current workflow: v1.19.4 candidate, PR #27. The published stable version
is v1.19.3 until a new draft is reviewed and published. The authoritative
security and signing policy is [docs/RELEASE_SECURITY.md](docs/RELEASE_SECURITY.md).

## 1. Pre-merge acceptance

- Freeze the release scope and verify the exact PR head.
- Resolve or explicitly document scanner findings and compatibility risks.
- Run the locked dependency resolution, strict Dart analysis and regression
  tests, Android JVM/lint checks, Rust checks and supply-chain verification.
- Review hosted checks on the final commit and the device acceptance matrix.
- Do not bypass required checks, alter signing identity, or overwrite releases.

Local Dart commands (Flutter 3.24.0, Dart 3.5 baseline):

    flutter pub get --enforce-lockfile
    flutter analyze
    flutter test --no-pub

Local or branch APKs are debug/test artifacts, not a signed public update.
Use disposable fixtures and the device test procedures in TESTING.md.

## 2. Version and build

The tracked pubspec.yaml is the version source of truth. Android Gradle reads
its version name/build number; iOS Info.plist uses Flutter build variables.
Do not manually replace these with hardcoded version values. Check that the
next build number exceeds the installed version for each supported variant.

Merge the accepted PR into main, verify the resulting commit, and confirm the
tag matches the pubspec version. Create an annotated tag on that exact commit
and push it. Never force-move an existing release tag.

The Build APK workflow produces signed Android APKs for ARM64, ARMv7 and
universal distribution, and an unsigned iOS IPA. The unsigned IPA is not an
installable production iOS application. Apple signing uses a separate
workflow; see IOS_SUPPORT.md.

## 3. Signing and publication

Keep the existing release signer. Do not generate a replacement keystore,
hardcode passwords in Gradle, or expose signing material in logs. CI uses
repository secrets and validates the pinned signing certificate.

Tagged builds run the release gates and stage a **draft** only after the
required artifact checks and both platform builds succeed. A draft is not a
prerelease or a published stable version. The release workflow refuses to
overwrite an existing release.

Review the actual APK checksums, signer, provenance attestations, SBOM,
native inventory, malware scan, MobSF/VT evidence and device acceptance.
Document unresolved findings and any deferred testing. Follow the release
security policy before publishing; do not claim independently audited or
malware-free status from automated scans.

After approval, publish the reviewed draft as a normal release, with
prerelease disabled. Confirm the public assets and release notes match the
verified candidate. See the current [GitHub releases](https://github.com/kiacoder/blackout-kit-mobile/releases).

## 4. Device acceptance and rollback

Verify an in-place update from the prior signed version using synthetic
configs, then check storage recovery, imports, Xray/sing-box connectivity,
DNS/IPv6 leak behavior, network transitions, revoke and kill switch.
iOS signed installation and tunnel behavior are independently unverified.

If a defect is found, preserve user data and evidence. Do not ask users to
uninstall, clear app data or replace signing keys to fix an upgrade.
Publish a corrected version with an increasing build number after retest;
do not silently replace a published APK or downgrade an encrypted library.
If appropriate, warn users about the affected version in release notes and
security advisories.

## 5. Optional distribution

App store distribution is separate from GitHub publication and is not
established by an APK or unsigned IPA build. Consult current store signing,
VPN entitlement and submission requirements before attempting distribution.
