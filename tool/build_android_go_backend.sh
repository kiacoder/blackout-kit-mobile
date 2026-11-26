#!/usr/bin/env bash
# Compile actual official AWG/WG JNI code. Development artifacts only, NOT app integration.
# Usage: script awg|wireguard SOURCE_DIR NEW_OUTPUT_DIR
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
engine="${1:?Choose awg or wireguard}"
source="$(cd "${2:?Official source directory}" && pwd)"
out="${3:?New output directory}"
[[ "$out" = /* ]] || out="$PWD/$out"
[[ ! -e "$out" ]] || { echo 'Refusing to overwrite output'; exit 1; }
case "$engine" in
  awg) pin=ff15093bf3856fea0947923474870b86efb682f0; module=github.com/amnezia-vpn/amneziawg-go/v3; subdir=amneziawg ;;
  wireguard) pin=e7b3a3c118836e112620b1302a8ba1873ad4daac; module=golang.zx2c4.com/wireguard; subdir=wireguard ;;
  *) exit 2 ;;
esac
[[ "$(git -C "$source" rev-parse HEAD)" == "$pin" ]]
git -C "$source" diff --quiet HEAD -- tunnel/tools/libwg-go
: "${ANDROID_NDK_HOME:?Set the development Android NDK path}"
: "${GO_BACKEND_ROOT:?Set a Go1.26.6 root patched with the pinned upstream boottime patch}"
patchfile="$source/tunnel/tools/libwg-go/goruntime-boottime-over-monotonic.diff"
echo "149ab7d9a1c20dad61fe279a837e0e0c81c6b2f5584614ac4d4cde67008755f0  $patchfile" | sha256sum -c -
# Verify the patch was applied; never quietly use unpatched suspend timers.
patch --dry-run -R -p1 -d "$GO_BACKEND_ROOT" < "$patchfile" >/dev/null
export GOROOT="$GO_BACKEND_ROOT" GOTOOLCHAIN=local
"$GOROOT/bin/go" version | grep -F 'go1.26.6 '
export GOPROXY="${GOPROXY:-file://$ROOT/.cache/$engine-modules/proxy}"
export GOMODCACHE="${GOMODCACHE:-$ROOT/.cache/$engine-gomod}"
# Build a disposable copy; never mutate pinned upstream or the verified cache.
work="$(mktemp -d "$ROOT/.cache/android-go-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp -a "$source/tunnel/tools/libwg-go/." "$work/"
"$GOROOT/bin/go" -C "$work" mod download
"$GOROOT/bin/go" -C "$work" mod verify
core="$("$GOROOT/bin/go" -C "$work" list -m -f '{{.Dir}}' "$module")"
cp -a "$core" "$work/core"
chmod -R u+w "$work/core"
"$GOROOT/bin/go" -C "$work" mod edit "-replace=$module=./core"
patch --fuzz=0 -p1 -d "$work/core" < "$ROOT/tool/patches/tun-consume-fd-on-error.patch"
if [[ "$engine" == awg ]]; then
  patch --fuzz=0 -p1 -d "$work/core" < "$ROOT/tool/patches/awg-refresh-padding-after-tun-read.patch"
fi
python3 "$ROOT/tool/prepare_android_go_bridge.py" "$work"
"$GOROOT/bin/gofmt" -w "$work/api-android.go"
export CGO_ENABLED=1 GOOS=android
library="libblackout-$engine.so"
export CGO_LDFLAGS="-Wl,-soname=$library -Wl,-z,max-page-size=16384"
mkdir -p "$out"
for abi in arm64-v8a armeabi-v7a; do
  if [[ "$abi" == arm64-v8a ]]; then
    export GOARCH=arm64; unset GOARM
    compiler=aarch64-linux-android24-clang
  else
    export GOARCH=arm GOARM=7
    compiler=armv7a-linux-androideabi24-clang
  fi
  export CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/$compiler"
  [[ -x "$CC" ]]
  mkdir "$out/$abi"
  "$GOROOT/bin/go" -C "$work" build -p 2 -mod=readonly \
    -tags linux -trimpath -buildvcs=false -buildmode=c-shared \
    -ldflags "-X $module/ipc.socketDirectory=/data/data/com.blackoutkit.vpn/cache/$subdir -buildid=" \
    -o "$out/$abi/$library" .
  python3 "$ROOT/tool/check_android_artifact.py" --binary "$out/$abi/$library" --abi "$abi" --min-sdk 24
  "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" -Ws "$out/$abi/$library" |
    awk '$7 != "UND" && $8 ~ /^Java_/ {print $8}' | sort -u > "$out/$abi/JNI_SYMBOLS.txt"
  if [[ "$engine" == awg ]]; then prefix=Java_org_amnezia_awg_GoBackend_awg
  else prefix=Java_com_wireguard_android_backend_GoBackend_wg; fi
  for method in TurnOn TurnOff GetSocketV4 GetSocketV6 GetConfig Version IsClosed; do
    grep -Fx "$prefix$method" "$out/$abi/JNI_SYMBOLS.txt" >/dev/null
  done
done
(cd "$out" && sha256sum */"$library" > SHA256SUMS)
printf 'Engine: %s\nSource revision: %s\nGo: 1.26.6 with upstream boottime patch\nAPI: 24\nStatus: COMPILED ONLY; not device-tested or packaged\n' "$engine" "$pin" > "$out/PROVENANCE.txt"
sha256sum "$ROOT/tool/prepare_android_go_bridge.py" "$ROOT/tool/patches/tun-consume-fd-on-error.patch" >> "$out/PROVENANCE.txt"
if [[ "$engine" == awg ]]; then
  sha256sum "$ROOT/tool/patches/awg-refresh-padding-after-tun-read.patch" >> "$out/PROVENANCE.txt"
fi
echo 'Native builds finished with distinct WG/AWG library names; no automatic app packaging.'
echo 'JNI/TUN ownership, invalid-config cleanup, log redaction, licenses and device tests remain gates.'
