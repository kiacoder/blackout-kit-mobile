#!/usr/bin/env bash
# Compiles production JVM-compatible engine code; no Android SDK/Gradle required.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to a Java 17+ runtime}"
KOTLINC="${KOTLINC:-kotlinc}"
mkdir -p .cache/host-tests
"$KOTLINC" \
  android/app/src/main/kotlin/com/blackoutkit/vpn/NativeChildStop.kt \
  android/app/src/main/kotlin/com/blackoutkit/vpn/VpnSessionExecutor.kt \
  android/app/src/main/kotlin/com/blackoutkit/vpn/EngineCommands.kt \
  android/app/src/main/kotlin/com/blackoutkit/vpn/ProcessCompat.kt \
  tool/kotlin/android/os/Build.kt \
  android/app/src/main/kotlin/com/blackoutkit/vpn/SubprocessLifecycle.kt \
  android/app/src/main/kotlin/com/blackoutkit/vpn/LocalSocksReadiness.kt \
  tool/kotlin/com/blackoutkit/vpn/EngineHostTests.kt \
  -jvm-target 17 -include-runtime -d .cache/host-tests/engines.jar
"$JAVA_HOME/bin/java" -cp .cache/host-tests/engines.jar com.blackoutkit.vpn.EngineHostTestsKt
