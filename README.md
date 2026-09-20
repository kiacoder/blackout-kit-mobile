# Blackout Kit Mobile - Open-Source VPN App

A trustworthy, open-source VPN client for Android and iOS built with Flutter. Fetches VPN configurations from GitHub, auto-tests them for reachability, and provides one-tap VPN connection.

**Status**: v1.0.0-beta.2 — Android tunnel implemented and building; not yet verified on hardware

> ⚠️ **Read this before testing.** The Android tunnel is now real: a Kotlin
> `VpnService` owns the TUN interface and the bundled Xray core runs in-process
> behind it. It **compiles, packages, and passes its unit tests**, but it has
> **never been run on a physical device** — no device was available while it was
> written. Treat the first run as a smoke test, not a working build.
>
> **Working protocols:** VLESS, VMess, Trojan, Shadowsocks, **WireGuard** — all
> five are carried in-process by the bundled Xray core. WireGuard does not need
> the sing-box binary: the shipped `libgojni.so` contains `xray.proxy.wireguard`.
> **Not working:** Hysteria2, TUIC, AmneziaWG, WARP and OpenVPN — the engine that
> would carry them is not bundled, and each fails with an explicit "engine not
> bundled" error rather than pretending to connect. Hysteria2 in particular
> cannot be served by the bundled core, which ships Hysteria **v1** only.
>
> [PHASES.md](PHASES.md) carries the authoritative, current phase status.

## Features

> The ✅ marks below describe the intended v1.0 feature set. Items marked 🟡 are
> implemented but unverified, or depend on an engine that is not bundled.

✅ **Config-based Architecture**
- Fetch VPN configs from trusted GitHub repositories
- Share-link parsing for 11 protocols (`vless://`, `vmess://`, `trojan://`,
  `ss://`, `hy2://`, `tuic://`, WireGuard `.conf`, `.ovpn`, AmneziaWG)
- Auto-deduplication by SHA256 hash
- Local encrypted storage with Hive

🟡 **Automatic Testing**
- Real TCP reachability and latency measurement per config
- Reliability scoring (0-100%) from repeated probes
- Config ranking by latency
- Non-blocking UI during tests
- **Throughput is not measured.** The earlier "speed test" derived a number from
  the config hash and never contacted anything; it has been removed rather than
  faked.

✅ **One-Tap Connection**
- Big connect button on home screen
- Auto-select fastest reachable config
- Real-time connection status and uptime
- Kill switch (holds the tunnel open if the engine dies)

✅ **Config Library**
- Browse all downloaded configs
- Filter by protocol
- Sort by latency, name, or recently added
- Quick details view with metrics
- Add custom GitHub repository sources

✅ **Settings Management**
- Auto-connect on launch
- Theme selection (light/dark/system)
- Language preferences
- Split tunneling (per-app, real `PackageManager` list)
- DNS leak prevention
- Protocol preference
- Auto-test intervals

## Architecture

### Tech Stack
- **Framework**: Flutter 3.22+
- **State Management**: GetX (reactive .obs, dependency injection)
- **Local Storage**: Hive (encrypted key-value)
- **VPN Bridge**: Platform channels (Android/iOS native)
- **Testing**: Unit + Integration tests

### Patterns
This app replicates architectural patterns from Blackout Kit CLI for consistency:

| Pattern | Purpose |
|---------|---------|
| **Registry** | Engine discovery (V2 extensibility) |
| **Factory** | Config parsing from multiple protocols |
| **Config Model** | Abstract base + protocol-specific subclasses |
| **Atomic Persistence** | Write-to-temp + move for safety |
| **State Machine** | VPN connection lifecycle |
| **Dependency Injection** | GetX services for decoupling |
| **GitHub Integration** | Cached API calls with TTL |

### Project Structure
```
lib/
├── models/              # Data models (Config, TestResult, Source)
├── services/            # Business logic (GitHub, Config, Tester, VPN)
├── controllers/         # GetX state management
├── screens/             # UI screens (Home, Library, Settings)
├── widgets/             # Reusable UI components
└── main.dart            # App entry + GetX setup
```

## Setup

### Prerequisites
- Flutter 3.22 or higher
- Dart 3.0+
- Android SDK 24+ or iOS 12+
- Git

### Installation
```bash
# Clone the repository
git clone https://github.com/blackout-kit/blackout-kit-mobile.git
cd blackout-kit-mobile

# Get dependencies
flutter pub get

# Run the app (Android)
flutter run --release

# Run the app (iOS)
cd ios
pod install
cd ..
flutter run --release -d <device-id>
```

## Usage

### First Run
1. App automatically fetches configs from trusted sources (GitHub)
2. Automatic speed/reliability test begins (3-5 minutes)
3. Home screen shows fastest working config
4. Tap the big connect button to activate VPN

### Add Custom Config Source
1. Open Library tab
2. Tap the "+" button in app bar
3. Enter GitHub repository info (owner, repo, branch)
4. Confirm — app fetches and tests configs

### Manage Settings
1. Open Settings tab
2. Toggle preferences (auto-connect, kill switch, theme, etc.)
3. Set preferred protocol or auto-select fastest
4. Changes save automatically

## Testing

### Unit Tests
```bash
flutter test
```

134 tests across five files:

```bash
flutter test test/config_parsing_test.dart
flutter test test/xray_config_test.dart
flutter test test/vpn_session_options_test.dart
flutter test test/services/engine_availability_test.dart
flutter test test/services/localization_service_test.dart
```

If `flutter test` dies with `WebSocketException: Invalid WebSocket upgrade request`,
a proxy in your environment is intercepting the runner's loopback socket. See the
note in `PHASES.md` for the workaround.

### Integration Tests
```bash
flutter test integration_test/app_flow_test.dart
flutter test integration_test/engine_hub_test.dart
```

> These run against mocked platform channels. They pass on a machine where the
> tunnel cannot start at all, so they are regression cover for Dart logic — not
> proof that the app can connect.

### Native Tunnel Test — **requires a physical device, never yet run**

```bash
adb shell appops set com.blackoutkit.vpn ACTIVATE_VPN allow   # skip the consent dialog
flutter test integration_test/native_tunnel_test.dart -d <device-id>
```

This is the only test that talks to the real `android.net.VpnService`. It asserts
that `prepare()` succeeds, that `Builder.establish()` brings the tunnel up, that
the in-process Xray core starts, that an unbundled protocol is refused rather
than black-holed, and that disconnect tears the interface down. It also holds the
tunnel open for 20 seconds so you can check `adb shell ip addr show tun0` from
another shell.

It has never been run, because no Android hardware has been available. It is the
test that closes this project's top open risk.

### Manual Testing Checklist

Dart-level:
- [ ] App starts and fetches configs from GitHub
- [ ] Configs auto-deduplicate by hash
- [ ] Reachability testing completes without freezing the UI
- [ ] Library shows correct config count and filtering works
- [ ] Settings persist after app restart
- [ ] Add custom source adds configs to library
- [ ] Engine Hub reports the real bundled-engine count, not 10

On a physical device (**nothing below has ever been run**):
- [ ] `VpnService.prepare()` consent dialog appears and is accepted
- [ ] `Builder.establish()` succeeds and the key icon appears in the status bar
- [ ] The Xray core starts and `isRunning` reports true
- [ ] Traffic actually flows — load a page through the tunnel
- [ ] `10.111.222.1/30` interface pairs with the `10.111.222.2/30` core gateway
- [ ] Disconnect tears the interface down cleanly
- [ ] Kill switch holds the tunnel open when the core is killed
- [ ] Split tunneling routes only the selected apps

## Roadmap

> **Last corrected: 2026-09-19.** Earlier revisions of this section listed the
> kill switch, split tunneling and DNS leak prevention as future work while
> marking the VPN integration "complete". Neither was accurate: the native
> tunnel did not exist, and those three features were implemented as calls to
> method channels that had no native handler. See `PHASES.md` for the
> authoritative per-phase status.

### Phase 1 — Foundation ✅ Complete
- Project setup with GetX + Hive
- Config models and share-link parsing for all 11 protocols
- GitHub service with caching
- Config persistence

### Phase 2 — VPN engine ✅ Complete
- Real `VpnService` tunnel in Kotlin (`BlackoutVpnService`)
- Xray core bundled and running **in-process** via `libv2ray` (`XrayEngine`)
- Dart-side Xray config generation with a `tun` inbound
- Connection state machine, honest error surfacing
- **Working protocols:** VLESS, VMess, Trojan, Shadowsocks, WireGuard

### Phase 3 — Security features ✅ Complete (corrected design)
- **Split tunneling** — `addAllowedApplication` / `addDisallowedApplication`,
  fed from a real `PackageManager` app list
- **DNS leak prevention** — `addDnsServer` plus in-core resolution
- **Kill switch** — holds the TUN open when the engine dies; reports Android's
  always-on VPN state and deep-links to the setting
- These are `VpnService.Builder` inputs, so they are applied at connect time.
  The earlier "activate after connecting" design was not implementable.

### Phase 4 — Tests, docs, release ✅ Complete
- 134 real unit tests covering Xray config generation, option validation,
  share-link parsing and engine-availability gating
- R8 + resource shrinking
- **APK size:** fat release APK 109.8 MB (down from 354 MB debug); per-ABI splits
  **57.6 MB (arm64-v8a) / 52.6 MB (armeabi-v7a)**
- Unused Xray geo databases excluded (−7.5 MB on disk)
- Unreferenced screenshots removed from the asset bundle (−2.6 MB per split)
- Corrected README / PHASES status claims

### Phase 4b — Bugs found while auditing the phase claims ✅
- **Saved VLESS / VMess / Trojan / Hysteria2 / TUIC configs were dropped from the
  library on every app start.** `ConfigService._configFromMap` had explicit
  branches only for WireGuard, OpenVPN and Shadowsocks and returned `null` for
  everything else; `getAllConfigs()` discards nulls. Every record now falls back
  to re-parsing its stored `rawUri`, and a round-trip test covers all six.
- **`xhttp` was emitted as a transport name the bundled core does not know.**
  Share links using `type=xhttp` or `type=splithttp` were normalised to
  `network: "xhttp"`. A byte scan of `libgojni.so` finds `splithttp` 14 times and
  the literal `xhttp` never — only the settings key `xhttpSettings`, which is a
  different thing. Both spellings now normalise to `splithttp`.
- **WireGuard profiles lost their `AllowedIPs`, `PresharedKey` and
  `PersistentKeepalive`**, and the parser wrote `[Interface] Address` into the
  field the UI shows as the *server*, so the config list displayed the device's
  own tunnel IP as the host. `validate()` also used `||` where both halves are
  required.
- **WireGuard now runs at all.** See the Phase 5 note below.
- **The engine hub's availability count used `any`, not `every`.** AmneziaWG
  lists `['amneziawg', 'wireguard']` and WARP lists `['warp', 'wireguard']`, so
  both cards would have shown as available the moment WireGuard became
  servable — despite neither engine being bundled. The rule is now
  `engineIsRunnable` (tested), and the honest count is **3 of 10**.

### Phase 5 — Remaining work ⏳
- [x] ~~Bundle a sing-box binary so Hysteria2 / TUIC / WireGuard / AmneziaWG /
      WARP can connect.~~ **Narrowed to four protocols.** WireGuard was removed
      from this list after the bundled `libgojni.so` was found to contain
      `xray.proxy.wireguard`; it now runs in-process with no new dependency and
      no licence change. The remaining four — Hysteria2, TUIC, AmneziaWG and
      WARP — still need sing-box, which is GPL-3.0 while this project is MIT, so
      that remains a licensing decision as well as a technical one.
- [ ] iOS native layer (`NEVPNManager`) — currently unregistered mocks
- [ ] **On-device verification of the tunnel (never run on real hardware)**
      — `integration_test/native_tunnel_test.dart` is written and waiting
- [ ] Current IP display — the native side returns a hardcoded `null`
- [ ] Localization coverage — the app shell is translated into 9 languages; ~96
      strings in `lib/screens` and `lib/widgets` are still English-only

## V2 Extensibility

The app is designed to scale to Blackout Kit V2 engines without UI changes:

```dart
// Add new protocol without modifying UI:
abstract class Config {
  String get protocol;
  Future<bool> connect();
}

// V2 engines register like this:
EngineRegistry.register('v2ray', V2RayConfig);
EngineRegistry.register('trojan', TrojanConfig);

// UI automatically discovers and displays them
```

## Threat Model & Security

### What This App Protects Against
- ISP monitoring of visited websites
- Regional censorship (content blocking)
- Man-in-the-middle attacks on public WiFi
- IP address leaks

### Limitations
- Trusts configured VPN servers (supply chain security)
- No protection against application-level leaks (DNS, WebRTC)
- VPN provider can see your traffic
- No multi-hop routing

### Open Source for Transparency
- All code visible on GitHub
- No closed-source binaries
- Community code review
- Reproducible builds planned

## Contributing

### To Report Issues
1. Check existing issues first
2. Open a new issue with:
   - Device model and OS version
   - Exact steps to reproduce
   - Error messages or logs
   - Expected vs actual behavior

### To Contribute Code
1. Fork the repository
2. Create a branch: `git checkout -b feature/amazing-feature`
3. Follow the code patterns (see Architecture section)
4. Add tests for new features
5. Keep commits atomic and descriptive
6. Open a pull request with description

### Code Standards
- Follow Flutter/Dart conventions
- Use GetX for state management (not Provider)
- Hive for persistence (not SQLite)
- No commented-out code or debug prints
- Tests required for new features

## License

Open-source under the MIT License. See [LICENSE](LICENSE) for details.

## Disclaimer

**Use at your own risk.** This VPN app is for educational purposes and comes with no warranty. Users are responsible for:
- Complying with local laws regarding VPN use
- Choosing trustworthy VPN servers
- Understanding the limitations (see Threat Model)
- Protecting their credentials and private keys

## Acknowledgments

- Flutter and Dart teams for the framework
- GetX author for the state management library
- Hive for encrypted local storage
- Community members testing and contributing

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Security**: security@blackout-kit.dev (or open private security issue)

---

**Made with ❤️ by Blackout Kit contributors**
