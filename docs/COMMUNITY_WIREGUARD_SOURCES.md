# Community WireGuard sources

Reviewed 2026-11-24. Built-in opt-in sources; existing Barry-Far and
V2Ray Aggregator defaults are unchanged. Enable in Settings and refresh
the library. These sources are third-party public configuration feeds,
not audited VPN providers. Shared client private keys are not private;
simultaneous clients may conflict. Never treat import or a feed's
health claim as proof of connectivity or privacy.

| Repository | Exact file | Local parser result |
|---|---|---|
| https://github.com/morpheusadam/v2ray-config | subs/bundles/wireguard.txt | 374 WireGuard profiles |
| https://github.com/Au1rxx/free-vpn-subscriptions | output/protocol/wireguard/singbox-0001.json | 613 WireGuard profiles |

Both exact files were fetched over HTTPS from the laptop and parsed
without printing or storing their credentials. Counts change over time,
are per source before cross-source deduplication, and do not mean a
successful handshake or traffic test. Au1rxx's first shard is intentionally
bounded; the second shard is not fetched. The repository declares MIT;
morpheusadam's README claims MIT but GitHub metadata returned no license.
Neither software license verifies authorization or safety of individual
upstream VPN accounts. No credentials are vendored.

The parser converts authority-style wireguard:// links and single-peer
sing-box WireGuard endpoints to native .conf. AWG parameters supported by
the existing native path are preserved. Unsupported extensions (including
nonzero reserved bytes, noise, and ifp/ifps) are refused rather than
discarded. Only the exact feed is fetched; no unrelated-file fallback.

No compatible, sufficiently documented AWG-only public static feed was
verified. The AWG entries in morpheusadam's feed used unsupported ifp/ifps
fields. Do not label those as compatible or import other people's private
client profiles. For a unique profile, use a provider-authorized .conf
or an explicitly requested per-device generation flow. References:
https://amnezia.org/free (official app-based free service; not an automatic
third-party .conf feed); https://docs.amnezia.org/documentation/instructions/connect-via-config/;
https://github.com/HereIamGosu/amnezia-config-gen (unofficial generator,
not a static config feed; review compatibility and provider terms before
integrating). No automatic registration/generator calls added.

Validation: 568 Flutter tests passed, including five new regressions.
Real feed parsing succeeded; no live tunnels tested. Native Test 6
contains the local Test 4/5 fixes and this source expansion.
