#!/usr/bin/env bash
# Narrow compile check: real Android API jar + bundled core API, without Gradle.
# Optional Flutter Java declarations allow VpnPlugin type-checking.
# Does NOT compile Flutter Java/Dart, resources or an APK, or run Android code.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME}"
: "${ANDROID_API_JAR:?Set ANDROID_API_JAR to Android API 34 android.jar}"
KOTLINC="${KOTLINC:-kotlinc}"
mkdir -p .cache/android-api-check
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('android/app/libs/libcores.aar') as archive:
    with open('.cache/android-api-check/cores.jar', 'wb') as output:
        output.write(archive.read('classes.jar'))
PY
cat > .cache/android-api-check/Generated.kt <<'KOTLIN'
package com.blackoutkit.vpn
// Compile-only substitutes for AGP-generated fields and a class literal.
object BuildConfig { const val ENABLE_EXPERIMENTAL_MIHOMO = false; const val ENABLE_EXPERIMENTAL_NATIVE_TUNNELS = false }
object R { object drawable { const val ic_vpn_notification = 1 } }
class MainActivity : android.app.Activity()
KOTLIN
EXTRA_SOURCES=()
if [[ "${CHECK_FLUTTER_PLUGIN:-false}" == true ]]; then
  python3 tool/fetch_flutter_compile_api.py
  EXTRA_SOURCES+=(android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt android/app/src/main/kotlin/com/blackoutkit/vpn/SiteProbeRunner.kt)
  while IFS= read -r -d '' file; do EXTRA_SOURCES+=("$file"); done < <(find .cache/flutter-api-source -name '*.java' -print0)
fi
"$KOTLINC" \
  android/app/src/main/kotlin/com/blackoutkit/vpn/{NativeChildStop,VpnSessionExecutor,OneShotCallbackSlot,EngineCommands,ProcessCompat,EngineRunner,SubprocessLifecycle,LocalSocksReadiness,BlackoutVpnService,TunnelCleanup,BlackoutCoreEngine,EmbeddedCoreOwner,LibboxEngine,XrayEngine,NativeTunnelConfig,NativeTunnelEngine,NativeTunnelLifecycle,GoRuntimeAdmission}.kt \
  android/app/src/main/kotlin/com/wireguard/android/backend/GoBackend.kt \
  android/app/src/main/kotlin/org/amnezia/awg/GoBackend.kt \
  .cache/android-api-check/Generated.kt "${EXTRA_SOURCES[@]}" \
  -cp "$ANDROID_API_JAR:.cache/android-api-check/cores.jar" \
  -jvm-target 17 -d .cache/android-api-check/service.jar
echo "Android source API check passed (plugin declarations: ${CHECK_FLUTTER_PLUGIN:-false}). NOT an APK build, Flutter Java/Dart compilation or device test."
