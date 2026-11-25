#!/usr/bin/env bash
# Only for disposable Linux CI runners; never boot or modify a user's AVD.
set -euo pipefail
: "${GITHUB_ACTIONS:?GitHub Actions runner required}"
: "${ANDROID_HOME:?Android SDK required}"
: "${RUNNER_TEMP:?Runner temp required}"
api="${1:?API level required}"
case "$api" in 24|34) ;; *) echo "Unsupported fixture API" >&2; exit 2 ;; esac
sdk="$ANDROID_HOME/cmdline-tools/latest/bin"
tools="$ANDROID_HOME/build-tools/34.0.0"
adb="$ANDROID_HOME/platform-tools/adb"
emulator="$ANDROID_HOME/emulator/emulator"
serial=emulator-5554
image="system-images;android-$api;google_apis;x86_64"
log="$RUNNER_TEMP/storage-emulator.log"
"$sdk/sdkmanager" "platform-tools" "build-tools;34.0.0" "emulator" "$image"
test -c /dev/kvm
sudo chmod a+rw /dev/kvm
"$emulator" -version
"$emulator" -accel-check
"$adb" start-server
"$adb" devices -l
# Refuse any existing device, rather than claiming it as our fixture.
if "$adb" devices | grep -Eq '^[^[:space:]]+[[:space:]]+(device|offline|unauthorized)'; then
  echo "Existing ADB device detected" >&2
  exit 1
fi
echo no | "$sdk/avdmanager" create avd --name storage-fixture --package "$image" --device pixel_2
"$emulator" -list-avds
"$emulator" -avd storage-fixture -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader -feature -Vulkan -accel on -verbose > "$log" 2>&1 &
emulator_pid=$!
cleanup() {
  code=$?
  trap - EXIT
  if (( code != 0 )); then
    echo "::group::Emulator startup/test diagnostics"
    "$adb" devices -l || true
    tail -n 160 "$log" || true
    echo "::endgroup::"
  fi
  kill "$emulator_pid" 2>/dev/null || true
  exit "$code"
}
trap cleanup EXIT
deadline=$((SECONDS + 420))
while (( SECONDS < deadline )); do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    echo "Emulator exited before Android booted" >&2
    exit 1
  fi
  if [[ "$(timeout 5 "$adb" -s "$serial" get-state 2>/dev/null || true)" == device ]] &&
     [[ "$(timeout 5 "$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)" == 1 ]]; then
    break
  fi
  sleep 3
done
if (( SECONDS >= deadline )); then
  echo "Android boot did not complete within the deadline" >&2
  exit 1
fi
"$adb" -s "$serial" shell input keyevent 82
python3 tool/run_storage_migration_acceptance.py --folder .cache/storage-fixtures-output --aapt "$tools/aapt" --apksigner "$tools/apksigner" --adb "$adb" --serial "$serial" --output migration-result.json
