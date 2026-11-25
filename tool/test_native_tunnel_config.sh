#!/usr/bin/env bash
# JVM-only parser regression; no Android/Flutter build claim.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to a Java 17 runtime}"
KOTLINC="${KOTLINC:-kotlinc}"
mkdir -p .cache/host-tests
"$KOTLINC" android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelConfig.kt \
  tool/kotlin/com/blackoutkit/vpn/NativeTunnelConfigTests.kt -jvm-target 17 -include-runtime \
  -d .cache/host-tests/native-config.jar
"$JAVA_HOME/bin/java" -jar .cache/host-tests/native-config.jar
