# Competitive feature matrix — Project Blackout

Baseline: maintainer update, 2026-11-27. This is a planning ledger, not an audited comparison or release capability claim. Prioritize OpenVPN and Mihomo before the remaining expansion.

| Feature | Blackout Kit Mobile status |
| --- | --- |
| Xray / VLESS / VMess / Trojan / Shadowsocks | Existing runtime; preserve regressions |
| sing-box / Hysteria2 / TUIC / AnyTLS | Maintainer reports working; exact build and protocol evidence required for release |
| Native WireGuard and AmneziaWG | Maintainer reports working; this branch still has a debug acceptance gate |
| OpenVPN | Private Android service candidate with certificate and interactive auth paths; no live authentication or device verification |
| Mihomo | Experimental adapter; API 24 artifacts built; Android traffic pending |
| Tor, Psiphon, Geph, Lantern, WARP/MASQUE | Planned or catalogue-only; feasibility and licensing review required |
| Independent Rust core | Experimental; not a complete replacement |
| FLUX, scanning, failover, site checks | Existing functionality; retain regression coverage |
| Split tunneling, DNS-only, DNS catalogue, kill switch | Existing implementation; verify per-engine behavior |
| Nexus adaptive routes and network learning | Planned |
| Pulse diagnostics, Sentinel, Engine Hub 2.0 | Planned |
| Config Studio, gaming optimization | Planned |
| Comparative benchmarks | Planned; controlled, reproducible testing required |

Reference competitor: [MLM VPN](https://github.com/mlmvpn/mlmvpn_android). Competitor claims and latest releases must be independently checked before publication. Do not infer security, speed, or full protocol support from catalogue entries. See [engine acceptance](OPENVPN_MIHOMO_ACCEPTANCE.md) and [v1.20.0 plan](V1_20_0_PLAN.md).
