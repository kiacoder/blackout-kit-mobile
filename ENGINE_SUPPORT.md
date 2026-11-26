# Engine support — source audit, 2026-11-16

> **2026-11-16 continuation update (supersedes older evidence below):** overall ~26%.
> Latest preservation/security/build review: [review](docs/CONTINUATION_REVIEW.md).
> Official-release-hash-verified Mihomo Linux core: **11 integration tests passed**.
> **30 JVM host tests / 33 Python tests passed (29 factory + 4 artifact checks); eleven-file Android API check passed, including VpnPlugin against official Flutter Java declarations.**
> Android ARM64 candidate verified but API34-targeted, NOT packaged/device-tested.
> Mihomo remains disabled by default; no APK/full Flutter build or server deployment.
> See [detailed evidence and limitations](docs/MIHOMO_CORE_PROGRESS.md).


**An experimental Mihomo adapter is now implemented, but disabled by default and NOT connection-tested. No new native engine is production-ready.**
An imported profile, bundled file, compiled program and verified tunnel are different states.

| Engine | Existing Android path | Change in this work | Verification here |
|---|---|---|---|
| Xray | libv2ray + TUN; VLESS/VMess/Trojan/SS/WG | Conservative batch share-link export | Source review only |
| sing-box | subprocess + tun2socks; alternative libbox binding | Bounded checker replaces unbounded output capture; shared CLI contracts | Service/runner source API-compiled; 23 host helper tests; no device tests |
| Mihomo | Experimental subprocess + existing TUN/SOCKS bridge; default OFF, binary absent | Full-document import, provider/group/rule preservation, native check dispatch | Service/runner source API-compiled; no native engine build or traffic test |
| AmneziaWG | No runnable backend | Detect newer AWG fields; preserve raw configs; never downgrade to WG | Python tests; Dart tests added, not run |
| Native WireGuard | None; existing WG uses Xray outbound | Offline multi-peer file packaging | Python tests only |
| OpenVPN | Parser only | Offline file preservation; no hook execution | Python tests only |
| blackout-core | Experimental Rust JNI/FFI | No runtime changes | Most dispatch paths explicitly unsupported |

ShadowTLS is a camouflage protocol needing an inner proxy. WARP is a service;
REALITY/TLS/WebSocket/gRPC/XHTTP are security/transport choices, not extra engines.
Psiphon/custom SNI/MHRV catalogue entries are not new working backends.

Upstream licensing observations and integration alternatives: [audit](docs/EXPANSION_AUDIT.md).
Next gate for each engine: exact source revision and notices → reproducible ABI artifacts
→ engine-native config check → TUN integration → traffic/DNS/reconnect/leak/device tests.
