# Changelog

All notable changes to Blackout Kit Mobile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta.5] - 2026-10-07

### Fixed
- **Config fetching returned nothing**: both built-in sources were invented
  placeholders — `free-vpn-configs/configs` and `open-vpn-community/free-configs`
  — and both return HTTP 404 from the GitHub API. Every fetch silently produced
  zero configs. Replaced with two repositories verified against the network.
- **Repository switches could not be turned off**: `loadSources()` merged the
  hardcoded defaults ahead of stored state and de-duplicated keeping the first
  entry, so the default's `isEnabled: true` overwrote whatever the user had
  saved. `TrustedSources.getEnabled()` additionally dropped disabled built-ins
  from the list entirely, so a turned-off source disappeared instead of showing
  an off switch. Stored state now wins and all built-ins are always listed.
- **Removing a repository did not stick**: `removeSource()` only dropped the
  entry from the in-memory list; the next load read it back from storage.
- **Startup would have hung once fetching worked**: `testAllConfigs()` used the
  sequential `TesterService.testConfigs` — one probe at a time, up to 4s x 3
  attempts each — against the ~7.6k configs a real source now returns. It uses
  `testConfigsConcurrently` with a bounded sample of 150 instead.
- **Source filtering was O(n²)**: `getFilteredConfigs()` called
  `getConfigsBySource()` per config, and that re-reads the whole Hive box.
  Source hashes are now resolved once into a `Set`.

### Added
- **barry-far/V2ray-Config** (`All_Configs_Sub.txt`, ~7.6k configs: vless, ss,
  trojan, vmess, hysteria2, hy2) as a built-in source.
- **mahdibland/V2RayAggregator** (`Eternity.txt`, ~200 configs: ss, trojan,
  vmess) as a second built-in source, on its real default branch `master`.
- `ConfigSource.filePath`, so a source can name the file that holds its configs
  instead of the fetcher guessing through eight filenames per branch — none of
  which these repos use.
- A `flutter analyze` step in CI. The unit tests never import screens or
  controllers, so a type error in `lib/` previously reached a release build
  unchecked.

### Changed
- The retired placeholder source IDs (`trusted-1`, `trusted-2`) are purged from
  storage on load, so upgraded installs do not keep showing two dead entries.

## [1.0.0-beta.4] - 2026-10-07

### Fixed
- **CI APK builds now work**: `android/gradle.properties` carried a tracked
  `org.gradle.java.home=C:/Users/kiacoder/java17`. Because the file is committed,
  that Windows path was also evaluated on `ubuntu-latest`, and every tagged build
  failed at configuration time with `Java home supplied is invalid`. Gradle falls
  back to `JAVA_HOME`, which CI sets explicitly, so the line was removed.
- **Version no longer silently `1`**: `android/app/build.gradle` read
  `flutter.versionCode` / `flutter.versionName`. Those are *methods* in Flutter
  3.22.0 (CI) but *getters* in Flutter 3.24.0 (dev machine), so the build failed
  on CI while working locally; and both implementations fall back to `1` / `1.0`
  when `local.properties` is missing, which it always is on a runner. The version
  is now parsed from `pubspec.yaml`, so `1.0.0-beta.4+4` yields versionName
  `1.0.0-beta.4` and versionCode `4`.

### Changed
- **One APK build, not two**: `build.yml` and `release.yml` both triggered on `v*`
  and both built and uploaded identically named APKs to the same release. APK
  production now lives only in `build.yml`, which also supports manual dispatch
  and always uploads an Actions artifact.

### Note on beta.3
- The `v1.0.0-beta.3` tag was created at `9625761`, *before* `252a9be` bundled
  sing-box and tun2socks, and its two workflows both failed, so no CI-built APK
  was ever produced for it. The APKs currently attached to that release were not
  built by CI. beta.4 is built from `main` and includes `252a9be`.

## [1.0.0-beta.3] - 2026-10-06

### Added
- **Bundled sing-box & tun2socks Core**: Compiled and bundled native `libsingbox.so` and `libtun2socks.so` for Android `arm64-v8a` and `armeabi-v7a`.
- **Active Protocol Execution**: Enabled full tunnel connection support for **Hysteria 2**, **TUIC v5**, **AmneziaWG** (obfuscated WireGuard with junk packets), and **WARP**.
- **SingboxConfigBuilder**: Created Dart configuration builder for sing-box routing, inbounds, outbounds, DNS protection, and split tunneling.

### Fixed
- **Settings Repository Layout**: Fixed column stretching and layout squishing that caused repository card labels to wrap one character per line.
- **Protocol Filtering**: Expanded Config Library filter bar to support all 10+ core protocols (All, VLESS, VMess, Trojan, Shadowsocks, WireGuard, Hysteria 2, TUIC, OpenVPN, AmneziaWG, WARP, Psiphon).
- **Subscription Ingestion**: Added automatic Base64 subscription decoding and embedded markdown/HTML URI extraction to `ConfigParser.parseMultiple`.
- **Repository Ingestion**: Updated `GitHubService.fetchConfigsFromSource` to search across candidate files (`configs.txt`, `subscription.txt`, `sub.txt`, `all.txt`, `vpn.txt`, `nodes.txt`, `v2ray.txt`, `README.md`) on both `main` and `master` branches.
- **Static Analysis**: Resolved all unnecessary cast warnings.

## [1.0.0-beta] - 2026-01-15

### Added
- **Initial Release (Beta)**
- Config-based architecture fetching VPN configs from GitHub
- Support for WireGuard, OpenVPN, and Shadowsocks protocols
- Automatic speed and reliability testing in background
- One-tap VPN connection with smart server selection
- Config library with filtering (protocol, speed) and sorting options
- Comprehensive settings management (auto-connect, kill switch, protocol preference)
- Platform channels for Android/iOS native VPN integration
- Encrypted local storage with Hive
- GetX reactive state management
- Full unit test suite for models and services
- Integration tests for complete app flows
- Android VPN service implementation
- iOS VPN service implementation
- GitHub Actions CI/CD for automated testing and builds
- Comprehensive documentation (README, ARCHITECTURE, CONTRIBUTING, SECURITY)
- MIT open-source license

### Features
- **Home Screen**
  - Big connect button with animated state transitions
  - Real-time connection status (connected/disconnected)
  - Current IP address display
  - Quick stats: Speed, Total Configs, Working, Average Reliability
  - Status card with icon and protocol badge
  - Connection uptime counter

- **Config Library Screen**
  - Browse all downloaded VPN configs
  - Filter by protocol (All, WireGuard, OpenVPN, Shadowsocks)
  - Sort options (Fastest, Name A-Z, Recently Added)
  - Config details bottom sheet
  - Speed badges with color coding
  - Working/Failed/Untested status indicators
  - Latency and reliability metrics
  - Quick connect/delete actions
  - Add custom GitHub repository sources
  - Empty state with fetch button

- **Settings Screen**
  - VPN Settings: auto-connect, kill switch, block non-VPN traffic, split tunneling
  - Appearance: theme selection (System/Light/Dark), speed indicator
  - General: language selection, notifications, analytics
  - Protocol: preferred protocol, auto-select fastest, auto-test interval
  - Repositories: manage trusted and custom sources
  - Advanced: local connection logging
  - About: app version, GitHub link, privacy policy
  - Reset to defaults option

- **Testing & Performance**
  - Background speed testing in isolate (non-blocking UI)
  - Latency and reliability measurements
  - Config ranking by performance
  - Working config filtering
  - Speed badge color coding (green 50+, orange 20-50, red <20 Mbps)

- **Architecture**
  - Registry pattern for V2 extensibility
  - Factory pattern for protocol-agnostic parsing
  - State machine for VPN connection lifecycle
  - Dependency injection with GetX services
  - Atomic persistence with Hive
  - GitHub API caching with 1-hour TTL
  - Error handling and user feedback

### Known Limitations
- Kill switch: Not implemented (Phase 5)
- Split tunneling: Settings UI only, not implemented (Phase 5)
- DNS leak prevention: Not implemented (Phase 5)
- App-level leak protection: Not available (inherent limitation)
- Rate limiting: GitHub API 60 req/hour for anonymous users
- No multi-hop routing
- No reproducible builds yet

### Security
- Open-source code on GitHub for transparency
- No closed-source binaries
- Encrypted local storage (device-specific key)
- No backend API or telemetry
- No account system required
- Minimal permissions (VPN only)
- See [SECURITY.md](SECURITY.md) for complete threat model

### Testing
- 40+ unit tests for models and services
- 8+ integration tests for complete flows
- Tests cover: parsing, deduplication, ranking, error handling, state machines
- Automated testing via GitHub Actions

### Documentation
- [README.md](README.md) - Overview, setup, usage
- [ARCHITECTURE.md](ARCHITECTURE.md) - Design patterns, extensibility, V2/V3 roadmap
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development guidelines and contribution process
- [SECURITY.md](SECURITY.md) - Security policy, threat model, vulnerability reporting

### Development
- Built with Flutter 3.22+, Dart 3.0+
- GetX state management (v4.6+)
- Hive encrypted storage (v2.0+)
- http package for GitHub API
- logger package for debugging
- Fully typed Dart code

### Roadmap

#### Phase 4 (Current - v1.0-beta)
- ✅ Full test suite (unit + integration + E2E)
- ✅ Polish (animations, error handling, onboarding)
- ✅ GitHub release setup (open-source, APK builds)

#### Phase 5 (v1.1 - Next)
- Kill switch implementation (iptables on Android, PF on iOS)
- Split tunneling per-app
- DNS leak prevention (secure DNS)
- In-app logging and debugging tools
- Improved UI/UX and animations
- Localization (8+ languages)

#### V2 Future (Blackout Kit Engines)
- Internal V2Ray, Trojan, NaïveProxy implementations
- Drop-in replacement for GitHub configs
- Full control over engine behavior
- Seamless integration via registry pattern

#### V3 Future (Reverse-Engineered Hotspot Shield)
- Reverse-engineered Hotspot Shield protocol
- Ultra-fast connection (proprietary optimization)
- All features without their proprietary app

## [Unreleased]

### Fixed
- **Repository names rendered one letter per line in Settings → Repositories.**
  No code was splitting the string; the tile's usable width was collapsing and
  `Text` soft-wrapped down to a single glyph per line. `overflow: ellipsis`
  alone does not prevent this — it needs an explicit `maxLines`. The source name
  and the `owner/repo (branch)` subtitle are now capped at one line with an
  ellipsis, and the wrapping column stretches to the section's full width.
- **Engine names in the Engine Hub had the same defect** — `overflow: ellipsis`
  inside a `Flexible` with no `maxLines`. Capped at one line.
- The repository detail sheet now caps its title at two lines instead of
  wrapping indefinitely.

### Planned
- Native buildVariants for different feature sets
- Reproducible builds with published checksums
- In-app update checking
- Custom app icon themes
- Export/import of config sources
- Web dashboard for config management (optional, separate project)

---

## How to Upgrade

### From v1.0-beta to v1.1
- Backup your config sources (in Settings)
- Uninstall the old app
- Install the new version
- Your settings will be preserved (stored in encrypted local storage)

### Reporting Issues
If you encounter bugs in any version:
1. Check [existing issues](https://github.com/blackout-kit/blackout-kit-mobile/issues)
2. Open a new issue with:
   - Device model and OS version
   - App version
   - Steps to reproduce
   - Error messages or logs

### Security Issues
For security vulnerabilities, please email security@blackout-kit.dev instead of opening public issues.

---

**Maintained by**: Blackout Kit Contributors  
**License**: MIT  
**Repository**: https://github.com/blackout-kit/blackout-kit-mobile
