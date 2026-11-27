# Project Blackout — v1.20.0: Engine Expansion & Security

Status: development milestone, not a released build. Published version: v1.19.4 (43c6d91). Development target: 1.20.0+2065. Do not create the release tag until the acceptance gate is reviewed.

## Baseline (2026-11-27)

- v1.19.4: six tagged workflows and nine main workflows succeeded at 43c6d91.
- GitHub Dependabot: zero open alerts at the baseline query; this does not imply no vulnerabilities in vendored binaries or native dependencies.
- Code scanning: two open warnings (#42 SiteProbeRunner.kt, #43 VpnPlugin.kt), both missing-certificate-pinning.
- MobSF universal APK: 55/100, two high findings (minSdk 24, CBC), nine warnings and one info. ClamAV zero detections; VirusTotal unknown-file. [Release evidence](https://github.com/kiacoder/blackout-kit-mobile/releases/tag/v1.19.4).
- Physical v1.19.4 acceptance, independent audit, reproducible APK and device performance evidence remain open.
- Previous documentation PR #28 is the stacked base. Its release history and historical evidence remain intact.

## Immediate priorities

OpenVPN and Mihomo first. Track evidence in [engine acceptance](OPENVPN_MIHOMO_ACCEPTANCE.md) and retain the [competitive feature matrix](COMPETITIVE_FEATURE_MATRIX.md) for later expansion.

## Workstreams and gates

| Phase | Deliverables | Required acceptance | State |
| --- | --- | --- | --- |
| 0 | Freeze baseline, version, evidence ledger and agent documentation | Draft PR; version source; truthful published/development distinction | Started |
| 1 | Audit every tracked Markdown/README, links, source claims and historical notes | [Per-file inventory](DOCUMENTATION_AUDIT.md); reconcile claims with code and immutable CI; archive notices; no fake testimonials or SEO claims | Open |
| 2 | Storage and Android security | Authenticated vault migration, wrong-key/interruption/restore tests, minSdk support decision and device matrix, fresh signed APK static scans | Open |
| 3 | Dependency and supply-chain remediation | Resolve lockfiles; review Dart, Gradle, Rust, Go, iOS, actions and vendored binaries; no unresolved actionable alerts; artifact provenance and license notices | Open |
| 4 | Engine architecture | Shared session ownership, capability admission, cancellation, socket protection, teardown, fail-closed routing and diagnostics; extract controller responsibilities | Open |
| 5 | Native WireGuard and AmneziaWG | Combined Go runtime provenance, both ARM ABIs, native lifecycle, device traffic/DNS/reconnect, profile compatibility and safe rollback | Open |
| 6 | Mihomo | Compatible pinned artifact, license/distribution review, full profile rules/groups/providers, protected sockets, validation and device traffic | Open |
| 7 | OpenVPN | Compare compatible upstream APIs/licenses, safe profile handling, no imported script execution, verified Android tunnel and credential lifecycle | Open |
| 8 | Xray and sing-box upgrades | Version compatibility, native inventory, exact protocol/transport matrix, configuration regressions, device traffic, no loss of currently supported functionality | Open |
| 9 | Independent Rust core | Authenticated transports, IPv4/IPv6, protected sockets, DNS, TCP/UDP, bounded flows, cancellation and interoperability; no direct fallback for unsupported proxy paths | Open |
| 10 | Remaining catalogue entries | Evaluate Shadowsocks, ShadowTLS, WARP, Psiphon and relay entries; distinguish actual engines from transports/services; only ship eligible, tested integrations | Open |
| 11 | Platform, reliability and performance | Signed iOS device acceptance if credentials/hardware are available; Android upgrade, network switching, kill switch, background, DNS/IPv6 tests; reproducibility and measured battery/CPU/RAM/throughput | Open |
| 12 | Release acceptance | Full CI, fresh hash-bound security evidence, device matrix, human review, changelog, signed APK integrity, no misleading release claims | Open |

## Engine promotion contract

An engine must move through: planned → source integrated → artifact verified → host tested → Android device verified → shipping. Parsing support is not engine support. Keep experimental runtimes default-off until acceptance, and avoid unsupported Connect actions. Test actual traffic, DNS, socket protection, cancellation, handover, reconnect, failure and kill-switch behavior on authorized fixtures. Preserve existing working engines until replacements are independently accepted. Do not ship arbitrary scripts or unreviewed binaries.

## Security target

Target MobSF 100/100 and zero open security/dependency findings. This is an aspiration, not a claim or a guaranteed achievable score. Record exact scanner version, signed APK hash, findings, disposition and regression tests. Never suppress findings, alter scanner output, remove functioning security checks, or weaken TLS to improve a metric. Review the two certificate-pinning warnings in the context of user-selected HTTPS destinations and third-party services; do not introduce brittle developer-controlled pins or unsafe trust overrides. If a rule is inapplicable, document evidence and maintainer review explicitly. If a genuine blocker remains, report it and keep the release gate open for a decision. No claim of malware-free status or independent audit from CI alone.

## Documentation and discoverability

Write clear human- and agent-readable facts: supported platforms, exact published release, engine matrix, license, source locations, verification scope, install instructions, security and limitations. Keep historical results dated. Maintain [AGENTS.md](../AGENTS.md), [llms.txt](../llms.txt), [current status](../CURRENT_STATUS.md), [release history](RELEASE_HISTORY.md) and [engine support](../ENGINE_SUPPORT.md). Do not attempt to manipulate AI recommendations; users and agents should be able to determine fit from accurate, verifiable evidence.

## Release discipline

Work on this draft PR in small reviewable commits. Never overwrite existing releases, change signing identity, discard user data, bypass CI or publish v1.20.0 before explicit acceptance. Update the evidence ledger after each milestone. Keep dependency changes narrow and compatible; record failures as failures. See [engineering acceptance](ENGINEERING_ACCEPTANCE.md), [release security](RELEASE_SECURITY.md) and [testing](../TESTING.md).
