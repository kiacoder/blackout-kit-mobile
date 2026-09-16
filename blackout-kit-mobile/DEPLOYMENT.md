# Deployment & Release Guide

Complete guide for testing, deploying, and releasing Blackout Kit Mobile to production. 📦

## Table of Contents

1. [Release Checklist](#release-checklist)
2. [Version Bumping](#version-bumping)
3. [Build & Sign](#build--sign)
4. [Beta Testing](#beta-testing)
5. [Production Release](#production-release)
6. [Rollback Procedures](#rollback-procedures)
7. [Monitoring](#monitoring)

---

## Release Checklist

Before releasing a new version, complete these steps:

### Pre-Release (1 week before)

- [ ] **Feature freeze** - Stop accepting new features
- [ ] **Bump version** - Update `pubspec.yaml`, `CHANGELOG.md`
- [ ] **Merge PRs** - Ensure all changes are merged to main
- [ ] **Run full test suite** - `flutter test` must pass 100%
- [ ] **Code analysis** - `flutter analyze` should have zero errors
- [ ] **Manual testing** - Test app on real Android and iOS devices
  - [ ] Connect/disconnect VPN
  - [ ] Switch between servers
  - [ ] Check IP address changes
  - [ ] Test all settings
  - [ ] Verify no leaks (DNS, WebRTC)

### Release Day

- [ ] **Create release branch** - `git checkout -b release/v1.0.0`
- [ ] **Update version tag** - Create git tag: `git tag -a v1.0.0 -m "Release v1.0.0"`
- [ ] **Push tag** - GitHub Actions automatically builds and creates release
- [ ] **Wait for CI** - Verify test.yml and build.yml pass
- [ ] **Verify artifacts** - Check APK and IPA appear in GitHub Releases
- [ ] **Create release notes** - Write user-friendly summary on GitHub

### Post-Release

- [ ] **Announce** - Post to GitHub Discussions, social media
- [ ] **Monitor** - Watch for issues in first 24-48 hours
- [ ] **Quick-fix** - If critical bug found, follow [Hotfix](#hotfix-release) process

---

## Version Bumping

Semantic versioning: **MAJOR.MINOR.PATCH**

### When to Bump

| Change | Version | Example |
|--------|---------|---------|
| New features | Minor | v1.0 → v1.1 |
| Bug fixes | Patch | v1.0.0 → v1.0.1 |
| Breaking changes | Major | v1.x → v2.0 |
| Beta/pre-release | Add suffix | v1.0.0-beta.1 |

### How to Bump

**File: `pubspec.yaml`**
```yaml
version: 1.0.0+1  # Format: VERSION+BUILD_NUMBER
```

**File: `CHANGELOG.md`**
```markdown
## [1.0.0] - 2026-01-15
### Added
- Feature A
- Feature B
```

**File: `android/app/build.gradle`** (Android)
```gradle
android {
    defaultConfig {
        versionCode 1        // Increment for every release
        versionName "1.0.0"  // Match pubspec.yaml
    }
}
```

**File: `ios/Runner/Info.plist`** (iOS)
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

---

## Build & Sign

### Android APK Build

**Local Build** (for testing):
```bash
flutter clean
flutter pub get
flutter build apk --release
```

APK is at: `build/app/outputs/flutter-app-release.apk`

**Automated Build** (GitHub Actions):
- Push a git tag (e.g., `git push origin v1.0.0`)
- GitHub Actions runs `build.yml` workflow
- Automatically uploads APK to GitHub Releases

### iOS IPA Build

**Local Build** (for testing):
```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

IPA generated at: `build/ios/Release-iphoneos/`

**Automated Build** (GitHub Actions):
- Same process as Android (tags trigger workflow)
- GitHub Actions builds on macOS runner
- Uploads IPA to releases

### Signing (Production)

For Play Store / App Store submission, you need code signing.

**Android Signing Key:**
```bash
# Generate keystore (one-time)
keytool -genkey -v -keystore ~/key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias blackout-key

# Reference in build.gradle
signingConfigs {
    release {
        keyStore = file("path/to/key.jks")
        keyStorePassword = "password"
        keyAlias = "blackout-key"
        keyPassword = "password"
    }
}
```

**iOS Signing Certificate:**
- Requires Apple Developer Account (paid)
- Generate certificate in Apple Developer portal
- Download and install in Xcode

---

## Beta Testing

### TestFlight (iOS)

1. **Build on macOS:**
   ```bash
   flutter build ios --release
   ```

2. **Archive in Xcode:**
   ```bash
   xcodebuild -workspace ios/Runner.xcworkspace \
     -scheme Runner -configuration Release -archivePath archive.xcarchive
   ```

3. **Upload to TestFlight:**
   - Open Xcode → Organizer → Archives
   - Select archive → Distribute App
   - Choose TestFlight → Upload
   - Wait for Apple review (~1 hour)

4. **Invite Testers:**
   - Open [App Store Connect](https://appstoreconnect.apple.com)
   - Go to TestFlight → Testers
   - Add tester emails

### Google Play Beta

1. **Build APK:**
   ```bash
   flutter build apk --release
   ```

2. **Upload to Google Play Console:**
   - [Open Play Console](https://play.google.com/console)
   - Your app → Release → Internal / Alpha / Beta testing
   - Upload APK
   - Fill release notes
   - Start rollout (~2 hours for review)

3. **Invite Testers:**
   - Create Google Group: `blackout-kit-mobile-testers`
   - Add tester emails
   - Share link in releases: `https://play.google.com/store/apps/details?id=com.blackoutkit.vpn`

### GitHub Pre-Release

For early access (not through app stores):

```bash
# Create pre-release tag
git tag -a v1.0.0-beta -m "Beta release"
git push origin v1.0.0-beta

# GitHub Actions builds and marks as pre-release
# Testers download directly from Releases page
```

---

## Production Release

### Day of Release

**1. Final Verification**
```bash
# Run tests one last time
flutter test

# Analyze code
flutter analyze

# Build locally to verify no errors
flutter build apk --release
```

**2. Bump Version & Commit**
```bash
# Edit pubspec.yaml, CHANGELOG.md, etc.
# Commit changes
git commit -am "chore: bump to v1.0.0"
```

**3. Create Release Tag**
```bash
# Create annotated tag (triggers CI/CD)
git tag -a v1.0.0 -m "Release v1.0.0"

# Push tag (GitHub Actions starts building)
git push origin v1.0.0
```

**4. Monitor CI/CD**
- Watch GitHub Actions: Settings → Actions
- Verify `test.yml` passes (40+ tests)
- Verify `build.yml` succeeds (APK + IPA created)
- Verify `release.yml` creates release page

**5. Create Release Notes**
- Go to GitHub Releases
- Edit the auto-generated release
- Add user-friendly summary
- Include highlight features
- Link to CHANGELOG.md
- Mark as "Release" (not pre-release)

**6. Publish to App Stores** (manual)

**Android Play Store:**
- Play Console → Your app → Release → Production
- Upload signed APK
- Fill release notes (copy from CHANGELOG.md)
- Review → Publish (~24 hours for review)

**iOS App Store:**
- App Store Connect → Your app → TestFlight
- Prepare for submission
- Add version info
- Add release notes
- Submit for review (~48 hours)

**7. Announce Release**
```
📢 Blackout Kit Mobile v1.0.0 is now available!

✨ Features:
- [Feature 1]
- [Feature 2]

🐛 Bug Fixes:
- [Fix 1]

📥 Download:
- [GitHub Releases link]
- [Play Store link]
- [App Store link]

🙏 Thanks to all contributors!
```

---

## Rollback Procedures

### If Release Has Critical Bug

**Immediate Actions (First 1 hour):**
1. **Pull from stores** (if possible):
   - Android: Play Console → Manage releases → Pause rollout
   - iOS: App Store Connect → Version release → Contact support to remove

2. **Pin previous version on GitHub:**
   - Edit release → Mark as "pre-release"
   - Update README to link to previous stable version

3. **Create hotfix branch:**
   ```bash
   git checkout -b hotfix/v1.0.1 v1.0.0
   # Fix the bug
   git commit -am "fix: critical bug"
   git push origin hotfix/v1.0.1
   ```

**Rollback Release:**
```bash
# Tag hotfix
git tag -a v1.0.1 -m "Hotfix: critical bug"
git push origin v1.0.1

# GitHub Actions rebuilds
# Test release thoroughly before publishing to stores
```

### If Build Fails

**Debug Build Failure:**
```bash
# Try building locally first
flutter clean
flutter pub get
flutter build apk --release -v  # verbose mode

# Check for:
# - Old Java version (need 11+)
# - Missing dependencies
# - SDK version mismatches
```

**Rollback to Previous Tag:**
```bash
# Delete broken tag
git push origin :v1.0.0  # or use GitHub web interface

# Fix issue
# Retry with same or new version
```

### If Tests Fail After Release

**Small Bug (can wait for next release):**
- Document in GitHub Issues
- Mark as non-critical
- Include fix in next version

**Critical Bug (needs immediate fix):**
- Create hotfix following hotfix-release process above
- Skip beta testing
- Go straight to production after local verification

---

## Monitoring

### Post-Release (First 48 hours)

**Check GitHub Issues:**
```bash
# Watch for new issues reported
# Label: [bug] [critical] for quick scanning
# Respond to users promptly
```

**Monitor Error Reports:**
- Check logs from users (if applicable)
- Look for patterns in error reports
- Escalate critical issues immediately

**Metrics to Track:**
- Download count
- User reports/feedback
- Crash reports (if integrated)
- Rating trends

### Long-term Monitoring

**Weekly:**
- Review closed issues
- Check dependency updates
- Look at GitHub Discussions

**Monthly:**
- Write release notes for next version
- Plan next minor release features
- Security audit of dependencies

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| **APK too large** | Use `--split-per-abi` to create architecture-specific APKs |
| **CI/CD timeout** | Increase timeout in workflow, or split into smaller jobs |
| **Play Store rejection** | Check policy compliance (privacy, permissions, content) |
| **App crashes on startup** | Enable stack traces, check device logs: `adb logcat` |
| **Version code mismatch** | Ensure `versionCode` is always higher than previous release |

---

## Release Schedule

**Planned Release Cycle:**

| Phase | Duration | Version | Focus |
|-------|----------|---------|-------|
| **v1.0-beta** | 4 weeks | Beta | Core features, testing, polish |
| **v1.0** | - | Stable | Production release |
| **v1.1** | 4-6 weeks | Minor | Kill switch, split tunneling, DNS |
| **v2.0** | TBD | Major | V2 engines (V2Ray, Trojan, etc.) |
| **v3.0** | TBD | Major | Reverse-engineered Hotspot Shield |

---

## Checklist for Next Release

- [ ] Version bumped in all files
- [ ] CHANGELOG.md updated
- [ ] Tests pass (100% ✓)
- [ ] Code analyzed (0 errors)
- [ ] Manual testing on real devices
- [ ] Security review of dependencies
- [ ] Release notes written
- [ ] Tag created and pushed
- [ ] CI/CD passes
- [ ] Artifacts verified
- [ ] Announced on social/forums
- [ ] Monitor for issues

---

**Questions?** Check GitHub Discussions or email security@blackout-kit.dev

**Last Updated:** 2026-01-15  
**Maintained By:** Blackout Kit Contributors
