#!/usr/bin/env bash
# Build WG + AWG behind ONE Go c-shared runtime for Android.
# Usage: build_android_combined_tunnels.sh WG_SOURCE AWG_SOURCE NEW_OUTPUT_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
wg_source="$(cd "${1:?WireGuard Android source}" && pwd)"
awg_source="$(cd "${2:?AmneziaWG Android source}" && pwd)"
out="${3:?New output directory}"
[[ "$out" = /* ]] || out="$PWD/$out"
[[ ! -e "$out" ]] || { echo 'Refusing to overwrite output'; exit 1; }

wg_pin=e7b3a3c118836e112620b1302a8ba1873ad4daac
awg_pin=ff15093bf3856fea0947923474870b86efb682f0
wg_module=golang.zx2c4.com/wireguard
wg_version=v0.0.0-20250521234502-f333402bd9cb
awg_module=github.com/amnezia-vpn/amneziawg-go/v3
awg_version=v3.1.20260814

[[ "$(git -C "$wg_source" rev-parse HEAD)" == "$wg_pin" ]]
[[ "$(git -C "$awg_source" rev-parse HEAD)" == "$awg_pin" ]]
git -C "$wg_source" diff --quiet HEAD -- tunnel/tools/libwg-go
git -C "$awg_source" diff --quiet HEAD -- tunnel/tools/libwg-go

: "${ANDROID_NDK_HOME:?Set Android NDK r22 path}"
: "${GO_BACKEND_ROOT:?Set patched Go1.26.6 root}"
wg_patch="$wg_source/tunnel/tools/libwg-go/goruntime-boottime-over-monotonic.diff"
awg_patch="$awg_source/tunnel/tools/libwg-go/goruntime-boottime-over-monotonic.diff"
for patchfile in "$wg_patch" "$awg_patch"; do
  echo "149ab7d9a1c20dad61fe279a837e0e0c81c6b2f5584614ac4d4cde67008755f0  $patchfile" | sha256sum -c -
  patch --dry-run -R -p1 -d "$GO_BACKEND_ROOT" < "$patchfile" >/dev/null
done

export GOROOT="$GO_BACKEND_ROOT" GOTOOLCHAIN=local
"$GOROOT/bin/go" version | grep -F 'go1.26.6 '

tmp_root="${BLACKOUT_COMBINED_TMPDIR:-$HOME/.cache/blackout-combined-builds}"
mkdir -p "$tmp_root"
work="$(mktemp -d "$tmp_root/build.XXXXXX")"
trap 'chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/modcache"

cat > "$work/go.mod" <<EOF
module blackout.local/tunnels

go 1.26

require (
    $wg_module $wg_version
    $awg_module $awg_version
    golang.org/x/sys v0.36.0
)
EOF
cat "$wg_source/tunnel/tools/libwg-go/go.sum" "$awg_source/tunnel/tools/libwg-go/go.sum" | sort -u > "$work/go.sum"
cp "$ROOT/tool/native_combined/api-combined.go" "$work/api-combined.go"
cp "$ROOT/tool/native_combined/jni-combined.c" "$work/jni-combined.c"

export GOPROXY="file://$ROOT/.cache/wireguard-modules/proxy,file://$ROOT/.cache/awg-modules/proxy"
export GOMODCACHE="$work/modcache"
export GOFLAGS=-buildvcs=false
"$GOROOT/bin/go" -C "$work" mod tidy
"$GOROOT/bin/go" -C "$work" mod download
"$GOROOT/bin/go" -C "$work" mod verify

wg_core="$("$GOROOT/bin/go" -C "$work" list -m -f '{{.Dir}}' "$wg_module")"
awg_core="$("$GOROOT/bin/go" -C "$work" list -m -f '{{.Dir}}' "$awg_module")"
cp -a "$wg_core" "$work/wg-core"
cp -a "$awg_core" "$work/awg-core"
chmod -R u+w "$work/wg-core" "$work/awg-core"
"$GOROOT/bin/go" -C "$work" mod edit "-replace=$wg_module=./wg-core"
"$GOROOT/bin/go" -C "$work" mod edit "-replace=$awg_module=./awg-core"

patch --fuzz=0 -p1 -d "$work/wg-core" < "$ROOT/tool/patches/tun-consume-fd-on-error.patch"
patch --fuzz=0 -p1 -d "$work/awg-core" < "$ROOT/tool/patches/tun-consume-fd-on-error.patch"
patch --fuzz=0 -p1 -d "$work/awg-core" < "$ROOT/tool/patches/awg-refresh-padding-after-tun-read.patch"

"$GOROOT/bin/gofmt" -w "$work/api-combined.go"
export CGO_ENABLED=1 GOOS=android
library=libblackout-tunnels.so
export CGO_LDFLAGS="-Wl,-soname=$library -Wl,-z,max-page-size=16384"

mkdir -p "$out"
for abi in arm64-v8a armeabi-v7a; do
  if [[ "$abi" == arm64-v8a ]]; then
    export GOARCH=arm64
    unset GOARM || true
    compiler=aarch64-linux-android24-clang
  else
    export GOARCH=arm GOARM=7
    compiler=armv7a-linux-androideabi24-clang
  fi
  export CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/$compiler"
  [[ -x "$CC" ]]
  mkdir -p "$out/$abi"
  "$GOROOT/bin/go" -C "$work" build -p 2 -mod=readonly -tags linux -trimpath -buildvcs=false -buildmode=c-shared -ldflags "-buildid=" -o "$out/$abi/$library" .

  command=(python3 "$ROOT/tool/check_android_artifact.py" --binary "$out/$abi/$library" --abi "$abi" --min-sdk 24)
  for prefix in Java_com_wireguard_android_backend_GoBackend_wg Java_org_amnezia_awg_GoBackend_awg; do
    for method in TurnOn TurnOff GetSocketV4 GetSocketV6 GetConfig Version IsClosed; do
      command+=(--require-symbol "${prefix}${method}")
    done
  done
  "${command[@]}"
done

(cd "$out" && sha256sum */"$library" > SHA256SUMS)
cat > "$out/PROVENANCE.txt" <<EOF
Artifact: combined WG/AWG Android JNI library
WireGuard source revision: $wg_pin
AmneziaWG source revision: $awg_pin
WireGuard core: $wg_module $wg_version
AmneziaWG core: $awg_module $awg_version
Go: 1.26.6 with pinned upstream CLOCK_BOOTTIME patch
API: 24
Design: one Go c-shared runtime; separate WG/AWG handle maps
Status: COMPILED ONLY until physical Android acceptance passes
EOF
sha256sum "$ROOT/tool/native_combined/api-combined.go" "$ROOT/tool/native_combined/jni-combined.c" "$ROOT/tool/patches/tun-consume-fd-on-error.patch" "$ROOT/tool/patches/awg-refresh-padding-after-tun-read.patch" >> "$out/PROVENANCE.txt"

echo "Built $library for ARM64 + ARMv7 with one Go runtime."
