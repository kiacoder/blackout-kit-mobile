#!/usr/bin/env bash
# Run only on an authorized private host. No push, upload, release or signing-key access.
# Default: preflight only. --build runs regressions and produces a DEBUG APK.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---check}"
[[ "$mode" == --check || "$mode" == --build ]] || { echo 'Use --check or --build'; exit 2; }
missing=0
need() { if command -v "$1" >/dev/null; then echo "FOUND $1"; else echo "MISSING $1"; missing=1; fi; }
for tool in flutter dart java javac python3; do need "$tool"; done
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -n "$sdk" && -f "$sdk/platforms/android-34/android.jar" ]]; then
  echo 'FOUND Android API 34'
else echo 'MISSING Android SDK platform android-34'; missing=1; fi
if [[ -n "$sdk" ]] && compgen -G "$sdk/build-tools/*/aapt2" >/dev/null; then
  echo 'FOUND Android build-tools'
else echo 'MISSING Android build-tools'; missing=1; fi
ndk="${ANDROID_NDK_HOME:-}"
if [[ -z "$ndk" && -n "$sdk" && -d "$sdk/ndk" ]]; then
  ndk="$(find "$sdk/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
fi
if [[ -n "$ndk" && -x "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" ]]; then
  echo 'FOUND Linux Android NDK compiler for API 24'
else echo 'MISSING Linux Android NDK compiler for API 24'; missing=1; fi
if [[ -n "$sdk" ]] && compgen -G "$sdk/cmake/*/bin/cmake" >/dev/null; then
  echo 'FOUND SDK CMake'
else need cmake; need ninja; fi
[[ "$missing" == 0 ]] || { echo 'BLOCKED: preflight incomplete; no build attempted.'; exit 2; }
java -version
javac -version
flutter --version
# Compare versions with the project pins before accepting results: Flutter3.24.0,
# Dart3.5+, Java17, compileSdk34, minSdk24, AGP7.4.2, Gradle7.6.6.
[[ "$mode" == --build ]] || { echo 'Preflight tools found; dependencies/versions still require build verification.'; exit 0; }
mkdir -p .buildlog/private-build
run() {
  local label="$1"; shift
  echo "RUN $label (private local log only)"
  "$@" > ".buildlog/private-build/$label.txt" 2>&1 || {
    echo "FAILED $label; inspect the private log before sharing it."; return 1;
  }
  echo "PASS $label"
}
# No dependency upgrades, release signing, server profiles or remote job dispatch.
run dependencies flutter pub get --enforce-lockfile
run analyze flutter analyze --no-fatal-infos --no-fatal-warnings
run flutter-tests flutter test test/ --coverage
run factory-tests python3 -m unittest discover -s tool/tests -v
run kotlin-tests bash -c 'cd android && ./gradlew --no-daemon :app:testDebugUnitTest'
run debug-apk flutter build apk --debug --target-platform android-arm,android-arm64
[[ -f build/app/outputs/flutter-apk/app-debug.apk ]]
sha256sum build/app/outputs/flutter-apk/app-debug.apk
echo 'DEBUG APK built. Android device/integration/VPN traffic tests are STILL REQUIRED.'
