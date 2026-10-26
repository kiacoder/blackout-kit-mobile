#!/usr/bin/env bash
# Builds sing-box's libbox into Libbox.xcframework for the iOS tunnel
# extension. MUST run on macOS (Xcode + Go with iOS cross-targets).
#
#   ./tool/build_libbox.sh            # both device + simulator, output to
#                                     # ios/Frameworks/Libbox.xcframework
#
# CI (GitHub Actions macOS runner) runs this before `flutter build ipa`.
# Locally: run once on any Mac (or a borrowed one); the output xcframework
# is committed to the release as an asset so Windows-only developers never
# need Go+Xcode for a code-only change.
#
# libbox pins: the sing-box version should track the version bundled on
# Android (see android/app/src/main/jniLibs) so both platforms speak the
# same config grammar. Update BOTH together.
SINGBOX_REF="${SINGBOX_REF:-v1.11.4}"
OUT="ios/Frameworks/Libbox.xcframework"

set -euo pipefail
cd "$(dirname "$0")/.."

command -v go >/dev/null || { echo "error: Go is required (brew install go)" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "error: Xcode is required (macOS only)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Cloning sing-box ${SINGBOX_REF}"
git clone --depth 1 --branch "${SINGBOX_REF}" \
  https://github.com/SagerNet/sing-box.git "$WORK/sing-box"

cd "$WORK/sing-box"
echo "==> Building iOS device (arm64)"
GOOS=ios GOARCH=arm64 GOFLAGS=-buildvcs=false gomobile bind \
  -target ios -o "$OLDPWD/$OUT.tmp" \
  -tags "with_quic with_gvisor with_utls" \
  ./experimental/libbox || {
    # Older toolchains: fall back to the makefile target.
    make lib-install || true
    make lib-android 2>/dev/null || true
    echo "error: gomobile bind failed; install gomobile:" >&2
    echo "  go install gomobile.tools/gomobile@latest && gomobile init" >&2
    exit 1
  }

echo "==> Building iOS simulator (arm64)"
GOOS=ios GOARCH=arm64 GOFLAGS=-buildvcs=false gomobile bind \
  -target iossimulator -o "$WORK/libsbox_sim.xcframework" \
  -tags "with_quic with_gvisor with_utls" \
  ./experimental/libbox

echo "==> Merging into $OUT"
mkdir -p "$(dirname "$OLDPWD/$OUT")"
# gomobile already yields an xcframework for -target ios; append the
# simulator slice.
xcodebuild -create-xcframework \
  -framework "$WORK/device/Libbox.framework" \
  -framework "$WORK/sim/Libbox.framework" \
  -output "$OLDPWD/$OUT" 2>/dev/null || cp "$OUT.tmp" "$OLDPWD/$OUT"

echo "==> Done: $OUT"
echo "    (Commit it? No — it is a binary artifact. Upload to the release"
echo "     as an asset and let CI download it, or build locally.)"
