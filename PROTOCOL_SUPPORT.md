# Protocol and transport matrix

This describes existing source paths, not live connectivity verified in this session.

| Protocol | Android source route | Constraints |
|---|---|---|
| VLESS / VMess | Xray | TLS/REALITY and transport compatibility depend on exact core and protocol |
| Trojan | Xray | Server TLS and transport must match |
| Shadowsocks / SS2022 | Xray | Exact cipher/key/core support required; not all SS methods interchangeable |
| Hysteria2 | sing-box | `hy2://` / `hysteria2://`; Hysteria v1 is now rejected, not re-labelled |
| TUIC | sing-box | v5 builder; incompatible with earlier protocol versions |
| AnyTLS | sing-box | Actual binary must implement it; iOS pinned libbox parity not verified |
| WireGuard | Xray outbound | Not official native Android WG backend; profile routes/DNS need device checks |
| AWG1 / newer variants / AWG2 | No runnable backend | Preserved config only; S3/S4/I1-I5 detection does NOT implement AWG2 |
| OpenVPN | No runnable backend | File import/packaging only |
| ShadowTLS | No complete standalone path | Requires inner proxy composition |

Xray builder exposes protocol-specific transport fields including TCP, WebSocket,
gRPC and XHTTP; do not assume that every combination is supported or that arbitrary
raw JSON can run through the app. iOS uses sing-box/libbox rather than Xray, and
its transport refusal checks must be preserved. DNS/routing/mux are constrained
builder options, not complete editor support for every upstream rule/rule-set.
Mihomo YAML preservation does not imply runtime support for its proxy types,
providers, health checks, failover, load balancing, TUN or DNS policies.

No protocol here is production-verified by this work. Server-specific protocol
matrix cannot be completed without inventory and authenticated test profiles.

Milestone 2: a default-OFF experimental Mihomo subprocess/SOCKS adapter now exists in
source. Its profile document may contain multiple proxy types, but no Mihomo binary or
protocol/server combination has been run here. Do not infer protocol support from its
YAML parser or catalogue entry. Fake-IP/native TUN/custom listeners are refused by the
bridge policy; groups/providers/rules are retained, with domain-routing caveats described
in CONFIGURATION_FORMATS.md. AWG catalogue requirements now explicitly require an AWG
backend, not sing-box or vanilla WireGuard.
