# Multi-engine expansion audit — 2026-11-16

## Scope and evidence
Baseline: `9c4213dc51b7c2c7c21bc34fb53f5ff760dcbb62`. This is a source-level
initial audit, not certification of every line or an on-device/server audit.
Inspected Flutter models, builders, persistence, controllers, engine catalogue,
Android manifest, Gradle, service/plugin/runners, JNI/native source inventory,
Rust dispatch, tests, and release workflows. No architecture replacement is justified
until current tunnels have a reproducible baseline on devices.

## Application structure
Flutter/GetX UI calls controllers and services. Config subclasses in
`lib/models/config.dart` parse URI and file profiles. ConfigService stores profiles,
sources and test results in Hive, with SecureVault migration and platform key storage.
VPNService uses platform channels; Android VpnPlugin starts BlackoutVpnService.
Engine hub intersects a broad family catalogue with native availability. The catalogue
mixes engines, protocols and services: ten entries do not mean ten working runtimes.
Existing UI covers QR scanning/sharing, files, subscriptions, logs, latency probes,
split tunneling, DNS options and failover. Preserve these paths rather than replace them.

## Engines and native boundary
* XrayEngine uses libv2ray/gomobile, configuration + TUN fd; generated JSON uses a
  TUN inbound and optional SOCKS inbound. Android accepts VLESS, VMess, Trojan,
  Shadowsocks and WireGuard. WireGuard here is an Xray outbound, NOT a native
  WireGuard Android backend and NOT AmneziaWG. Runtime version reporting exists.
* sing-box subprocess + tun2socks is the Android fallback. `fdlauncher.c` duplicates
  the TUN descriptor into the child; ProcessBuilder alone cannot pass it. Checker,
  SOCKS readiness and exit monitoring exist. ARM32/ARM64 binaries are checked in.
  LibboxEngine is an alternative binding. Availability currently tests presence,
  not every required feature or library ABI. Protocol allowlist is HY2/TUIC/AnyTLS.
* iOS builds libbox at v1.11.4 by default; Android comments describe newer schemas.
  Do not assume these versions support identical AnyTLS/WireGuard/routing syntax.
* Rust blackout-core includes JNI/FFI and a smoltcp netstack, but outbound dispatch
  explicitly refuses most advertised protocol implementations. `boringtun` dependency
  and AWG struct fields do not implement AmneziaWG. Only limited plain VLESS paths
  exist; do not promote this core to a production replacement.
* No Mihomo runner or YAML profile model. OpenVPN is parse-only. AmneziaWG is
  parse-only and native availability correctly excludes it. ShadowTLS is a TLS
  camouflage protocol requiring an inner proxy, not another complete VPN engine.

## Configuration and subscriptions
URI parser handles proxy links, base64/list subscriptions, WireGuard/AWG blocks,
OpenVPN and endpoint-gated custom profiles. Builders generate constrained JSON;
they are not arbitrary engine-document importers. No lossless Clash/Mihomo YAML
round-trip or complete arbitrary sing-box/Xray profile path exists. QR generation
is not proof a target client supports the encoded document. Deduplication largely
uses raw URI identity, not engine-equivalent semantic identity. Subscriptions and
cached test results exist; automatic updates must be tested against offline,
revoked, malformed and oversized responses.

## Lifecycle and reliability
Foreground special-use VpnService, consent, revoke/destroy teardown and kill-switch
blocked-state logic exist. START_NOT_STICKY is not persistent restart. Core/probe
exclusive ownership, network transitions, revoked consent, process death and FD
ownership require physical-device testing. SubprocessLifecycle.stop only requests
termination; runner also has its own teardown. Do not introduce an independent
VpnService backend that races the existing owner. Raw checker/log tails can carry
configuration secrets; sanitization/bounded output deserves follow-up. Existing
ConfigService 'quarantine' deletes corrupt legacy plaintext boxes: this is not a
recoverable backup. Encrypted-box failures are preserved instead.

## Confirmed parser correctness findings
1. `hysteria://` is accepted as Hysteria2 though v1 is a different wire protocol.
2. AWG detection only lists Jc/Jmin/Jmax/S1/S2/H1-H4. Profiles with newer S3/S4 or
   I1-I5 fields can be misclassified as standard WireGuard. Keep the original
   content and refuse unsupported execution; do not silently convert.
3. AWG numeric fields are a legacy subset: H ranges/new fields cannot be represented
   by nullable integers. Raw content survives; full backend validation remains needed.

## Security / supply chain / licensing
App requests Internet/network, foreground service, notifications, package installation,
all-package visibility for split tunneling, and camera through scanning dependencies.
Backups disabled. Configs contain credentials; exports and QR images are plaintext
secrets. Avoid logging raw imports and never check deployment bundles into Git.
Release signing is environment-dependent; tagged CI refuses missing release keys.
AAR dependencies are local files; release pipeline downloads/builds native assets.
Reproducible hashes, exact native source provenance, notices and source offers require
review before distributing a changed APK. Root MIT does not relicense bundled GPL,
LGPL or MPL components. No code from reference projects was copied in this work.

## Reference comparison (checked-out source revisions)
* kiacoder/blackout-kit `bd01813097665f56be4e371061c8c7574f7cbeae`: root MIT;
  Python management + Go engine wrapper. go.mod pins sing-box 1.13.14 and an Xray
  pseudo-version. Useful config/schema comparisons, not Android lifecycle code.
  Vendored components retain their own licenses.
* mlmvpn/mlmvpn_android `c56b89f7007776e725c9a5d4c8b52fa033af150f`: GPL-3.0;
  AmneziaWgInjector delegates to a separate `:awg` service process to avoid Go runtime
  collisions. Dependency `com.zaneschepke:amneziawg-android:2.1.13` is a candidate,
  not proof of official AWG version support. OpenVPN JNI exposes evaluate/create/run/
  stop/release. Useful ownership/IPC concepts; copying into MIT source requires
  deliberate license compliance. No runtime/device quality claim made.
* mlmvpn/mlmvpn_windows `4fa8bcecd2d2047b938b0da6fef62776fae19720`: custom MLMVPN
  Attribution License 1.0, explicitly source-available, not OSI-approved. Node
  managers for Xray/OpenVPN/WARP and other services are desktop orchestration, not
  reusable Android TUN adapters. Read for comparison; no code adaptation performed.

## Integration decisions and alternatives
Mihomo: evaluate maintained upstream Go library wrapper with Android socket protection
and TUN fd callbacks; alternatively loopback SOCKS + existing tun2socks, preserving
DNS/UDP and controller authentication. Full YAML must retain proxy groups/providers;
a flat URI conversion is not an equivalent profile. **Correction in milestone 2:**
the earlier MIT observation at 008b91bfe8c0e2daca0ab69061efd9ea1ad71bd2 was from a
default-branch tree describing a Python game API, NOT the VPN engine. The inspected
VPN release v1.19.34 at 0455d0d28c4526937380505153e65a843d8612e8 has module
`github.com/metacubex/mihomo` and a GPL-3.0 LICENSE. Use the pinned VPN source,
not default-branch metadata, for build/provenance/licensing decisions.
AWG: official Amnezia userspace backend or maintained Android binding in an isolated
service process. Verify AWG1/1.5/2 parameter grammar against pinned upstream, exact
server version, multiple peers and address/routes. Vanilla sing-box/WireGuard is not
an alternative AWG backend. WG: evaluate official Android tunnel backend with explicit
VpnService ownership migration, not simultaneous interfaces.
OpenVPN: maintained Android frontend/backend or OpenVPN3 JNI integration with protected
sockets, credentials callbacks, certificate verification and platform TUN callbacks;
external companion app is possible but not an integrated engine. Review component
licenses and supported directives (scripts/plugins must never execute on import).
Xray/sing-box: pin actual artifacts and validate feature documents against those exact
binaries before upgrading builders. XHTTP support must be version/engine-specific.

## Environment and server audit blockers
No flutter, dart, java, cargo, rustc, go or kotlinc on PATH; no Android SDK variables.
Network is restricted to GitHub/npm/Python package hosts. Downloading Flutter source
alone does not supply Dart/engine artifacts, Maven/Google dependencies or a device.
No release build or tunnel test can honestly be reported here.
All three servers ([private Frankfurt-1 address], [private Frankfurt-2 address], [private Netherlands address]) are NOT INSPECTED:
no authorized SSH account/port/key channel, host fingerprints or reachable route.
No connections, scans, writes or service changes attempted. IP addresses alone cannot
produce working profiles. User Downloads is not mounted; workspace is not that folder.

## Priority
Fix protocol misclassification; add offline lossless format packaging with explicit
validation levels and private output; record tests. Then provision toolchain/device,
license/provenance inventory, runtime adapters, engine checks and server access.
Do not call placeholders or configuration containers integrated engines.

Upstream AWG device/uapi.go at `08fe3d33bbb116be09a6183d02609311b8b0c9e8`
accepts S3/S4 and I1-I5 as well as legacy keys; detection fix is grounded in those
fields, not an assertion that the Android backend now supports AWG2. Official
AWG-Go root is MIT; AWG-Android and WG-Android roots Apache-2.0. OpenVPN3 LICENSE.md
offers AGPL-3.0 or MPL-2.0; inspect the chosen revision and dependencies before use.

## Native artifact follow-up
Read-only metadata extraction found sing-box v1.14.2 embedded in both Android
subprocess binaries, contrasting with the iOS build-script v1.11.4 pin. The AAR
contains Xray pseudo-version `v1.260327.1-0.20261031132019-a4a3dff5b20c` and a
sing-box replacement placeholder; that placeholder is not an identifiable release.
See NATIVE_ARTIFACTS.md for hashes. These observations do not prove runtime API,
ABI, licensing provenance or successful version execution on Android.
