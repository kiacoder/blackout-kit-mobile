#!/usr/bin/env bash
# Run the repository's existing Kotlin JUnit suite with real JUnit and a full JDK.
# No Gradle/Android runtime is used. NOT a full Android build.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to a full JDK17}"
KOTLINC="${KOTLINC:-kotlinc}"
[[ -x "$JAVA_HOME/bin/javac" ]]
source=.cache/references/junit4
if [[ ! -e "$source" ]]; then
  git clone --depth 1 --branch r4.13.2 https://github.com/junit-team/junit4.git "$source"
fi
[[ "$(git -C "$source" rev-parse HEAD)" == 05fe2a64f59127c02135be22f416e91260d6ede6 ]]
git -C "$source" diff --quiet HEAD -- src/main/java lib/hamcrest-core-1.3.jar
mkdir -p .cache/junit-classes
mapfile -d '' JAVA_SOURCES < <(find "$source/src/main/java" -name '*.java' -print0)
"$JAVA_HOME/bin/javac" -encoding UTF-8 -source 8 -target 8 \
  -cp "$source/lib/hamcrest-core-1.3.jar" -d .cache/junit-classes "${JAVA_SOURCES[@]}"
# Every current src/test file; fail compilation if a new test needs unavailable deps.
mapfile -d '' TEST_SOURCES < <(find android/app/src/test -name '*.kt' -print0)
"$KOTLINC" \
  android/app/src/main/kotlin/com/blackoutkit/vpn/{SubprocessLifecycle,LocalSocksReadiness,NativeTunnelLifecycle,NativeTunnelConfig}.kt \
  "${TEST_SOURCES[@]}" -cp ".cache/junit-classes:$source/lib/hamcrest-core-1.3.jar" \
  -jvm-target 17 -include-runtime -d .cache/kotlin-junit-tests.jar
CLASSES=()
for file in "${TEST_SOURCES[@]}"; do
  package="$(sed -n 's/^package //p' "$file" | head -1)"
  name="$(basename "$file" .kt)"
  CLASSES+=("$package.$name")
done
"$JAVA_HOME/bin/java" -cp ".cache/kotlin-junit-tests.jar:.cache/junit-classes:$source/lib/hamcrest-core-1.3.jar" \
  org.junit.runner.JUnitCore "${CLASSES[@]}"
