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
# AndroidX already ships in the app. Type-check against those exact pinned
# artifacts rather than inventing stub implementations of compatibility APIs.
for artifact in core core-ktx; do
  case "$artifact" in
    core) digest=2c27de199535675005553066597a4b20fa1eea7c228ab4ef6b32b5fe39ca1f59 ;;
    core-ktx) digest=19ba50d094c7368ede1b4ccf1195ceb83e35970736593f823e5af716f8d05d70 ;;
  esac
  archive=".cache/android-api-check/$artifact.aar"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 --max-time 120 \
      "https://dl.google.com/dl/android/maven2/androidx/core/$artifact/1.13.1/$artifact-1.13.1.aar" -o "$archive"
  fi
  printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -
done
# Keep annotations used by the native JNI bridge; pin the compile API.
annotation=".cache/android-api-check/annotation.jar"
if [[ ! -f "$annotation" ]]; then
  curl --fail --location --retry 3 --max-time 120 \
    "https://dl.google.com/dl/android/maven2/androidx/annotation/annotation-jvm/1.8.0/annotation-jvm-1.8.0.jar" -o "$annotation"
fi
printf '%s  %s\n' '9aab326d9492800991854360ac248f493ce7f7c3183519309b78ace9e240f6f6' "$annotation" | sha256sum -c -
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('android/app/libs/libcores.aar') as archive:
    with open('.cache/android-api-check/cores.jar', 'wb') as output:
        output.write(archive.read('classes.jar'))
for name in ('core', 'core-ktx'):
    with zipfile.ZipFile(f'.cache/android-api-check/{name}.aar') as archive:
        with open(f'.cache/android-api-check/{name}.jar', 'wb') as output:
            output.write(archive.read('classes.jar'))
PY
cat > .cache/android-api-check/Generated.kt <<'KOTLIN'
package com.blackoutkit.vpn
// Compile-only substitutes for AGP-generated fields and a class literal.
object BuildConfig { const val ENABLE_EXPERIMENTAL_OPENVPN = false; const val ENABLE_EXPERIMENTAL_MIHOMO = false; const val ENABLE_EXPERIMENTAL_NATIVE_TUNNELS = false }
object R { object drawable { const val ic_vpn_notification = 1 } }
class MainActivity : android.app.Activity()
KOTLIN
EXTRA_SOURCES=()
if [[ "${CHECK_FLUTTER_PLUGIN:-false}" == true ]]; then
  python3 tool/fetch_flutter_compile_api.py
  EXTRA_SOURCES+=(android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt android/app/src/main/kotlin/com/blackoutkit/vpn/TunnelDiagnosticPolicy.kt android/app/src/main/kotlin/com/blackoutkit/vpn/SiteProbeRunner.kt android/app/src/main/kotlin/com/blackoutkit/vpn/EngineCatalogue.kt android/app/src/main/kotlin/com/blackoutkit/vpn/ProbeEngineController.kt)
  while IFS= read -r -d '' file; do EXTRA_SOURCES+=("$file"); done < <(find .cache/flutter-api-source -name '*.java' -print0)
fi
"$KOTLINC" \
  android/app/src/main/kotlin/com/blackoutkit/vpn/{AvailableNetworkRegistry,AvailableNetworkMonitor,NativeChildStop,VpnSessionExecutor,OneShotCallbackSlot,EngineCommands,ProcessCompat,EngineRunner,EngineSessionAdmission,TransientEngineConfig,LegacyEngineConfigs,SubprocessLifecycle,LocalSocksReadiness,BlackoutVpnService,TunnelCleanup,BlackoutCoreEngine,EmbeddedCoreOwner,LibboxEngine,XrayEngine,NativeTunnelConfig,NativeTunnelEngine,NativeTunnelLifecycle,GoRuntimeAdmission,OpenVpnAndroidBackend,OpenVpnCandidateProfile,OpenVpnCredentials,OpenVpnNativeBridge,OpenVpnSession,OpenVpnTunCallbacks}.kt \
  android/app/src/main/kotlin/com/wireguard/android/backend/GoBackend.kt \
  android/app/src/main/kotlin/org/amnezia/awg/GoBackend.kt \
  .cache/android-api-check/Generated.kt "${EXTRA_SOURCES[@]}" \
  -cp "$ANDROID_API_JAR:.cache/android-api-check/cores.jar:.cache/android-api-check/core.jar:.cache/android-api-check/core-ktx.jar:.cache/android-api-check/annotation.jar" \
  -jvm-target 17 -d .cache/android-api-check/service.jar
echo "Android source API check passed (plugin declarations: ${CHECK_FLUTTER_PLUGIN:-false}). NOT an APK build, Flutter Java/Dart compilation or device test."
