#!/usr/bin/env bash
# Builds sing-box's libbox into Libbox.xcframework for the iOS tunnel
# extension. MUST run on macOS (Xcode + Go).
#
#   ./tool/build_libbox.sh          # output: ios/Frameworks/Libbox.xcframework
#
# Uses sing-box's own build_libbox tool and its PINNED gomobile fork
# (github.com/sagernet/gomobile) — the upstream gomobile does not carry the
# patches sing-box's libbox bindings need, and `make lib_install` pins the
# exact version. CI (GitHub Actions macOS runner) runs this before
# `flutter build ios`.
#
# libbox pins: SINGBOX_REF should track the version bundled on Android
# (android/app/src/main/jniLibs/libsingbox.so) so both platforms speak the
# same config grammar. Update BOTH together.
SINGBOX_REF="${SINGBOX_REF:-v1.11.4}"
OUT="$(pwd)/ios/Frameworks/Libbox.xcframework"

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

echo "==> Installing sing-box's pinned gomobile fork (make lib_install)"
make lib_install

echo "==> Building Apple framework (device + simulator)"
# build_libbox -target apple produces Libbox.xcframework for ios/arm64 +
# iossimulator/arm64 and writes it into the sing-box working tree.
go run ./cmd/internal/build_libbox -target apple
# debug=true would disable optimizations; release build by default.

BUILT="$WORK/sing-box/Libbox.xcframework"
[ -d "$BUILT" ] || BUILT="$(find "$WORK/sing-box" -maxdepth 2 -type d -name 'Libbox.xcframework' | head -1)"
[ -n "$BUILT" ] && [ -d "$BUILT" ] || { echo "error: Libbox.xcframework not produced" >&2; exit 1; }

echo "==> Installing to $OUT"
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"
ditto "$BUILT" "$OUT"

echo "==> Done: $OUT"
echo "    Binary artifact — do not commit. Upload to a release asset or"
echo "    let CI build it fresh."
