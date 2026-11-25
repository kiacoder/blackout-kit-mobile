#!/usr/bin/env bash
# Real production ownership coordinator with a fake native backend; not JNI/device testing.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to Java 17}"
KOTLINC="${KOTLINC:-kotlinc}"
mkdir -p .cache/host-tests
"$KOTLINC" android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelLifecycle.kt \
  tool/kotlin/com/blackoutkit/vpn/NativeTunnelLifecycleTests.kt -jvm-target 17 -include-runtime \
  -d .cache/host-tests/native-lifecycle.jar
"$JAVA_HOME/bin/java" -jar .cache/host-tests/native-lifecycle.jar
