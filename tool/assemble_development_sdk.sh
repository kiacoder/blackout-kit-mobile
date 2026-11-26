#!/usr/bin/env bash
# Assemble development platform/build-tools layout from a PINNED AOSP mirror.
# Not an official SDK Manager installation; no license acceptance is fabricated.
# Does not supply Flutter, platform-tools/adb, emulator or Gradle dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
source=.cache/toolchains/aosp-sdk
out="${1:-.cache/android-sdk}"
pin=3af7c93524be6f51e092b87b17f009f13ee98b43
[[ "$(git -C "$source" rev-parse HEAD)" == "$pin" ]]
git -C "$source" diff --quiet HEAD
[[ ! -e "$out" ]] || { echo 'Refusing to overwrite development SDK'; exit 1; }
mkdir -p "$out/platforms/android-34" "$out/build-tools/35.0.0"
cp "$source/34/public/"{android.jar,framework.aidl,core-for-system-modules.jar} "$out/platforms/android-34/"
cp -a "$source/tools/linux/bin/." "$out/build-tools/35.0.0/"
cp -a "$source/tools/linux/lib" "$source/tools/linux/lib64" "$out/build-tools/35.0.0/"
# These two discovery files are local assembly metadata, not upstream artifacts.
cat > "$out/platforms/android-34/source.properties" <<'META'
Pkg.Desc=Local development Android API 34 (pinned AOSP mirror)
Pkg.Revision=1
AndroidVersion.ApiLevel=34
AndroidVersion.CodeName=REL
Layoutlib.Api=15
Layoutlib.Revision=1
META
printf 'ro.build.version.sdk=34\nro.build.version.codename=REL\nro.build.version.release=14\n' > "$out/platforms/android-34/build.prop"
printf 'Development assembly from mirror %s\nPlatform discovery metadata generated locally. No official SDK/license certification.\n' "$pin" > "$out/PROVENANCE.txt"
"$out/build-tools/35.0.0/aapt2" version
smoke="$(mktemp -d .cache/sdk-smoke.XXXXXX)"
trap 'rm -rf "$smoke"' EXIT
mkdir -p "$smoke/smoke"
printf 'package smoke; interface Probe { void ping(); }\n' > "$smoke/smoke/Probe.aidl"
"$out/build-tools/35.0.0/aidl" --lang=java -I "$smoke" -o "$smoke/generated" "$smoke/smoke/Probe.aidl"
[[ -s "$smoke/generated/smoke/Probe.java" ]]
"$out/build-tools/35.0.0/d8" --version
"$out/build-tools/35.0.0/apksigner" version
echo 'Platform and build-tools assembled; full app build still required.'
