# Changelog

All notable changes to Blackout Kit Mobile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
