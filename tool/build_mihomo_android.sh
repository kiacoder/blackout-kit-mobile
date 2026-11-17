#!/usr/bin/env bash
# Build ONLY from the reviewed VPN release tag, never the repository's default
# branch. Requires a provisioned Go + Android NDK host with module access.
# Does NOT modify app binaries or claim a working tunnel.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed NDK}"
command -v go >/dev/null
command -v git >/dev/null
REF=v1.19.34
COMMIT=0455d0d28c4526937380505153e65a843d8612e8
OUT="${1:-$ROOT/.cache/mihomo-android-$REF}"
if [[ -e "$OUT" ]]; then echo 'Refusing to overwrite existing output.' >&2; exit 1; fi
mkdir -p "$ROOT/.cache"
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"
WORK="$(mktemp -d "$ROOT/.cache/mihomo-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Linux host only; do not silently choose an incompatible NDK host toolchain.
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
test -x "$TOOLCHAIN/aarch64-linux-android24-clang"
test -x "$TOOLCHAIN/armv7a-linux-androideabi24-clang"
git clone --depth 1 --branch "$REF" https://github.com/MetaCubeX/mihomo.git "$WORK/source"
test "$(git -C "$WORK/source" rev-parse HEAD)" = "$COMMIT"
grep -q '^module github.com/metacubex/mihomo$' "$WORK/source/go.mod"
grep -q 'GNU GENERAL PUBLIC LICENSE' "$WORK/source/LICENSE"
cd "$WORK/source"
# Use upstream checksums. Never turn off sumdb verification to bypass a network block.
go mod download
go mod verify
mkdir "$WORK/output"
for abi in arm64-v8a armeabi-v7a; do
  if [[ "$abi" == arm64-v8a ]]; then arch=arm64; compiler=aarch64-linux-android24-clang
  else arch=arm; compiler=armv7a-linux-androideabi24-clang; fi
  mkdir "$WORK/output/$abi"
  CGO_ENABLED=1 GOOS=android GOARCH="$arch" GOARM=7 CC="$TOOLCHAIN/$compiler" \
    go build -mod=readonly -buildmode=pie -tags with_gvisor -trimpath \
    -ldflags "-X github.com/metacubex/mihomo/constant.Version=$REF" \
    -o "$WORK/output/$abi/libmihomo.so" .
done
# Fail closed if compiler metadata exceeds the app API floor or ABI is wrong.
for abi in arm64-v8a armeabi-v7a; do
  python3 "$ROOT/tool/check_android_artifact.py" --binary "$WORK/output/$abi/libmihomo.so" --abi "$abi" --min-sdk 24
done
cp LICENSE "$WORK/output/LICENSE-mihomo"
printf 'Source: https://github.com/MetaCubeX/mihomo\nTag: %s\nCommit: %s\nStatus: built, NOT device-tested\n' "$REF" "$COMMIT" > "$WORK/output/PROVENANCE.txt"
(cd "$WORK/output" && sha256sum */libmihomo.so > SHA256SUMS)
# Consumers must additionally prepare corresponding source/notices for distribution.
mkdir "$OUT"
cp -a "$WORK/output/." "$OUT/"
echo "Built experimental artifacts in $OUT. Review licensing and test before packaging."
