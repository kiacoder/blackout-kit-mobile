# Android toolchain migration — Ascension Phase 3

Status: isolated toolchain CI tests and APK/iOS packaging passed (2026-11-25). PR20 build pins unchanged.

Candidate run 45443595453 completed successfully: APK build, signature and inventory checks, antivirus, SBOM, VirusTotal hash lookup, MobSF analysis and provenance steps succeeded. iOS unsigned IPA built. No release signing or publication was requested. Scanner execution success is not a clean security verdict; artifact findings and device behavior remain to be reviewed before promotion. Latest PR20 ShellCheck jobs also passed.

## GitHub acceptance checkpoint

- Candidate branch `experiment/ascension-android-toolchain`, commit `37be23c`, passed Tests workflow 45437373000, including Dart analyze/unit tests, Android JVM tests and lint. Integration test step reported no connected device; non-fatal by policy. This is not device or release APK acceptance.
- Local Gradle 8.7 binary distribution downloaded, extracted and independently SHA-256 verified. AGP 8.5.2 resolution remains blocked locally: official Google Maven endpoints returned HTTP 404 for 8.5.1, 8.5.2 and 8.6.1. Maven Central responded normally. Cached AGP 8.5.1 lacked plugin metadata; offline configuration failed. Restored intended 8.5.2.
- Full APK build and existing security pipeline dispatched on candidate: https://github.com/kiacoder/blackout-kit-mobile/actions/runs/45443595453 . No tag or publication requested.
- PR20 baseline e3c422d passed Tests, Android APK, Rust Android, security scans and one iOS build. Separate iOS job failed runner acquisition, with no build steps executed; GitHub annotated macOS arm64 capacity constraints. No source-code failure established.
- Promote candidate only after APK and security report review; physical Android tests and local dependency access remain outstanding.

## Experiment checkpoint

- Baseline e3c422d is pushed; both GitHub host checks passed (31 real JVM host tests and narrow Android API compile, not VPN device tests).
- Independent worktree: `C:\Users\kiacoder\blackout-kit-mobile-toolchain`, on `experiment/ascension-android-toolchain` at 37be23c. Candidate changes three build files: settings.gradle, app/build.gradle, and gradle-wrapper.properties.
- Candidate uses the smaller official Gradle 8.7 **bin** distribution; independently published SHA-256: `544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d`. Existing trusted wrapper JAR unchanged.
- Offline Flutter dependency resolution passed. Gradle distribution verification and candidate GitHub tests subsequently passed; local AGP resolution remains blocked.
- No experimental changes promoted to PR20.

## Baseline

- Flutter 3.24.0 in CI, AGP 7.4.2, Gradle 7.6.6, Kotlin 1.9.25, JDK 17.
- compile/target SDK 34, minimum SDK 24. AGP 7.4.2 was tested through API 33.
- Existing lint logs report Kotlin metadata 1.9 versus expected 1.7.1, even when Gradle exits successfully. The older lint analyzer is a suspect, not a proven root cause.
- The last local lint run returned 0 errors and 6 warnings; 40 Android JVM tests passed. Baseline privacy and host-test fixes were committed as e3c422d.
- All nine resolved Android plugins declare a namespace (flutter_secure_storage uses a conditional namespace call and declares AGP 8.5.1 in its own buildscript).

## Candidate bridge, not the final modern stack

| Component | Baseline | Candidate |
|---|---|---|
| AGP | 7.4.2 | 8.5.2 |
| Gradle | 7.6.6 | 8.7 |
| Kotlin | 1.9.25 | 2.0.21 |
| JDK | 17 | 17 |
| Flutter | 3.24.0 | 3.24.0 initially |
| min/compile/target API | 24/34/34 | unchanged |

Android documentation confirms the AGP 8.5 family supports API 34 and needs Gradle 8.7/JDK 17. JetBrains lists Kotlin 2.0.21 with AGP through 8.5 and Gradle 8.7 support for non-multiplatform projects. The combination is a candidate only: Flutter and all dependency plugins must be exercised together. Do not jump to AGP 9 while retaining Flutter 3.24.0.

## Local preflight blockers

- Original Gradle 8.7 all-distribution cache was incomplete; verified bin distribution is now installed.
- AGP 8.5.0/8.5.1 cached; 8.5.2 not cached. Kotlin 2.0.21 not cached.
- App defines custom BuildConfig fields; AGP 8 defaults require explicit buildFeatures.buildConfig = true.
- Flutter SDK Gradle plugin still compiles against AGP 7.3.0. Check its actual runtime compatibility rather than editing the installed SDK.
- Standalone Linux host tests passed in GitHub CI; local Linux JDK provisioning remains outstanding.

## Acceptance sequence

1. Use a separate experimental checkout; preserve PR20 local changes.
2. Obtain official Gradle 8.7 distribution and verify published SHA-256; pin the wrapper checksum. Resolve AGP/Kotlin from trusted repositories. Do not use unverified cache archives.
3. Update candidate pins and explicitly enable BuildConfig; keep minSdk, release feature flags, JNI packaging, signing and backup policy unchanged.
4. Run Gradle configuration, debug unit tests, lint, Flutter analyzer and full unit tests, and debug/release APK builds. Inspect Kotlin diagnostics and packaging.
5. Compare release ABI and manifest inventories, native artifacts, disabled experimental flags, signature verification, and device smoke tests (API 24/25 plus current Android). Re-run security scanners.
6. Align CI and private build preflight version documentation; verify wrapper integrity baseline if the wrapper JAR changes. Merge only after acceptance and review.
7. Schedule a separate supported Flutter/SDK upgrade; the intermediate stack is not a current long-term support recommendation.

References:
- https://developer.android.com/build/releases/agp-8-5-0-release-notes
- https://kotlinlang.org/docs/gradle-configure-project.html
- https://developer.android.com/build/kotlin-support
- https://gradle.org/release-checksums/
- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin
