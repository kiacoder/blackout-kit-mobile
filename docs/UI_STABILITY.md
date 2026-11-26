# UI stability follow-up

Reported symptom: intermittent crashes while opening screens or tapping controls
in the first side-by-side native Android test build. No device crash trace was
available during this investigation (ADB had no connected phone).

Fixed concrete Flutter defects:
- Engine Hub filters now use stable category IDs, not localized labels. Reactive
  subscriptions remain valid even with an empty category. Engine cards constrain
  badges and protocol chips for narrow screens.
- Import defers initial clipboard/share handling until the first frame, prioritizes
  explicit shared payloads, guards late scanner/clipboard callbacks and only closes
  the route associated with an asynchronous successful save.
- Editor suppresses duplicate saves and checks route ownership before navigation.
- Logs checks mounted after confirmation; the update checker checks mounted before
  initial state changes. Preferred-protocol dialog subscribes even when no engine
  is available.

Host verification: 554/554 Flutter tests passed, including three new interaction
regressions (Persian and Chinese Engine Hub filters at 360 logical pixels, and a
known empty engine capability report). Static analysis exits 0 with 200 existing
info-level findings. Native transport code is unchanged. These fixes do not
establish that the reported Android process crash is resolved; obtain a device
crash stack and reproduce on the next test APK. Do not claim physical acceptance
or production readiness.

## Follow-up: Engine Hub startup and local preflight (Native Test 3)

The user reported that Engine Hub would not open in Test 2. The Android capability
query was eagerly calling JNI version and availability methods for the merged
Xray/libbox Go runtime and the separate combined WG/AWG Go runtime. This is a
credible native process-crash path, not a confirmed diagnosis without device logs.

- Engine inventory now reads packaged library presence only; it makes no JNI
  calls and does not claim successful runtime initialization. Actual startup
  still checks the runtime. Catalogue queries no longer load native libraries.
- Process-wide atomic admission prevents loading both Go runtime families in a
  single process. Claims remain sticky even after stop or failed initialization.
  A full app restart may be required before switching families. Xray-backed
  WireGuard and the existing sing-box subprocess fallback are retained where
  available. The production gate remains disabled.
- Engine Hub capability timeout, one-pass profile counts, actual Settings
  navigation tests; protocol chooser rejects rapid duplicate taps and late
  replies; DNS/reset/add-source callbacks cannot pop unrelated routes.
- Narrow-screen benchmark header now wraps. Local navigation smoke covers Home,
  Library, Settings, Engine Hub/details, Guide, Logs, Split Tunneling, Benchmark,
  Add Source and Config Editor.
- Updated the physical acceptance suite so WG/AWG and embedded Xray tests use
  separate fresh processes. Passive inventory is no longer described as JNI
  acceptance. Physical runtime/handshake/traffic validation remains pending.

Local preflight results: Flutter 559/559 (including 9 Settings/navigation widget
tests); Android JVM 36/36 (including three runtime-admission tests); analyzer
exits 0, 201 informational findings, no errors or warnings. Native-enabled
side-by-side APK built and verified for both ARM ABIs. No GitHub push or CI
trigger in this round. Physical crash reproduction remains pending (no ADB
device connected).

Repeat locally before pushing:
- flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
- flutter test --no-pub
- From android: gradlew.bat :app:testDebugUnitTest
- powershell -ExecutionPolicy Bypass -File tool/build_native_debug_windows.ps1 -SideBySide

APK: release-assets/blackout-kit-1.19.2-native-test.3-arm-universal-debug.apk
SHA256: 54afbb591fd25eed4da657bb9a35644fafb567411b65a2b10a387fd36807691d
