#!/usr/bin/env bash
# Official core tests and Linux kernel fixtures. NOT Android instrumentation.
# Usage: script awg|wireguard SOURCE_DIR [--kernel]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
engine="${1:?Choose engine}"
source="$(cd "${2:?Official Android source directory}" && pwd)"
GO="${GO:-$ROOT/.venv/bin/go}"
case "$engine" in
  awg) pin=ff15093bf3856fea0947923474870b86efb682f0; module=github.com/amnezia-vpn/amneziawg-go/v3 ;;
  wireguard) pin=e7b3a3c118836e112620b1302a8ba1873ad4daac; module=golang.zx2c4.com/wireguard ;;
  *) exit 2 ;;
esac
[[ "$(git -C "$source" rev-parse HEAD)" == "$pin" ]]
git -C "$source" diff --quiet HEAD -- tunnel/tools/libwg-go
export GOTOOLCHAIN=local GOPROXY="file://$ROOT/.cache/$engine-modules/proxy"
export GOMODCACHE="$ROOT/.cache/$engine-gomod"
mkdir -p "$ROOT/.buildlog"
work="$(mktemp -d "$ROOT/.cache/backend-fixture.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp "$source/tunnel/tools/libwg-go/go.mod" "$source/tunnel/tools/libwg-go/go.sum" "$work/"
"$GO" -C "$work" mod download
"$GO" -C "$work" mod verify > "$ROOT/.buildlog/$engine-module-verification.txt"
# Copy both verified cores so lifecycle tests cover the same API in both engines.
core="$("$GO" -C "$work" list -m -f '{{.Dir}}' "$module")"
cp -a "$core" "$work/core"
chmod -R u+w "$work/core"
"$GO" -C "$work" mod edit "-replace=$module=./core"
patch --fuzz=0 -p1 -d "$work/core" < "$ROOT/tool/patches/tun-consume-fd-on-error.patch"
cp "$ROOT/tool/go_backend_tests/tun_fd_ownership_test.go" "$work/core/tun/"
cp "$ROOT/tool/go_backend_tests/device_liveness_test.go" "$work/core/device/"
if [[ "$engine" == awg ]]; then
  patch --fuzz=0 -p1 -d "$work/core" < "$ROOT/tool/patches/awg-refresh-padding-after-tun-read.patch"
  cp "$ROOT/tool/go_backend_tests/blackout_awg_test.go" "$ROOT/tool/go_backend_tests/awg_read_barrier_test.go" "$work/core/device/"
fi
"$GO" -C "$work" test -race -p 2 -count=1 -timeout=180s -json \
  "$module/device" "$module/conn" "$module/replay" "$module/tun" > "$ROOT/.buildlog/$engine-patched-core-rerun.jsonl" 2>&1
if [[ "$engine" == awg ]]; then
  "$GO" -C "$work" test -race -p 2 -count=20 -timeout=180s \
    -run '^(TestBlackoutAWGReadBeforeConfiguration|TestAWGDevicePing)$' \
    -json "$module/device" > "$ROOT/.buildlog/awg-patched-stress-rerun.jsonl" 2>&1
fi
if [[ "${3:-}" == --kernel ]]; then
  sed "s|github.com/amnezia-vpn/amneziawg-go/v3/|$module/|g" \
    "$ROOT/tool/go_backend_tests/kernel_peer.go" > "$work/main.go"
  "$GO" -C "$work" build -p 2 -mod=readonly -o "$work/peer" .
  python3 "$ROOT/tool/test_kernel_tunnel.py" --engine "$engine" --binary "$work/peer" \
    --report "$ROOT/.buildlog/$engine-patched-kernel-rerun.json"
fi
echo "PASS $engine requested test stages; inspect JSON logs for skipped upstream tests. NOT Android testing."
