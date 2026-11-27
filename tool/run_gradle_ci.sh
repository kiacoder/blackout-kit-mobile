#!/usr/bin/env bash
# Retry only a known pre-test plugin-resolution failure, never a failed test.
set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT
if bash ./gradlew --no-daemon "$@" 2>&1 | tee "$log"; then
  exit 0
else
  result=("${PIPESTATUS[@]}")
fi
# Preserve failures in either Gradle or its output capture.
if (( result[1] != 0 )); then
  exit "${result[1]}"
fi
if grep -Fq "Plugin [id: 'org.jetbrains.kotlin.android', version: '2.4.21', apply: false] was not found" "$log" &&
   grep -Fq "could not resolve plugin artifact 'org.jetbrains.kotlin.android:org.jetbrains.kotlin.android.gradle.plugin:2.4.21'" "$log"; then
  echo "Pinned Kotlin plugin resolution failed before tests; retrying once." >&2
  sleep 15
  # The exact same command must succeed. No fallback versions or skipped tasks.
  bash ./gradlew --no-daemon "$@"
else
  exit "${result[0]}"
fi
