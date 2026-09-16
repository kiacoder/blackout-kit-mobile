# Blackout Kit Mobile - Open-Source VPN App

A trustworthy, open-source VPN client for Android and iOS built with Flutter. Fetches VPN configurations from GitHub, auto-tests them for speed/reliability, and provides one-tap VPN connection.

**Status**: v1.0-beta (Phase 3 Complete)

## Features

✅ **Config-based Architecture**
- Fetch VPN configs from trusted GitHub repositories
- Support for WireGuard, OpenVPN, Shadowsocks protocols
- Auto-deduplication by SHA256 hash
- Local encrypted storage with Hive

✅ **Automatic Testing**
- Background speed and latency testing
- Reliability scoring (0-100%)
- Config ranking by performance
- Non-blocking UI during tests

✅ **One-Tap Connection**
- Big connect button on home screen
- Auto-select fastest working config
- Real-time connection status and IP
- Kill switch support (Phase 4)

✅ **Config Library**
- Browse all downloaded configs
- Filter by protocol (WireGuard, OpenVPN, Shadowsocks)
- Sort by speed, name, or recently added
- Quick details view with metrics
- Add custom GitHub repository sources

✅ **Settings Management**
- Auto-connect on launch
- Theme selection (light/dark/system)
- Language preferences
- Split tunneling (roadmap)
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
flutter test test/models/config_test.dart
flutter test test/services/tester_service_test.dart
```

### Integration Tests
```bash
flutter test integration_test/app_flow_test.dart
```

### Manual Testing Checklist
- [ ] App starts and fetches configs from GitHub
- [ ] Configs auto-deduplicate by hash
- [ ] Speed/reliability testing completes without freezing UI
- [ ] Connect button changes color when connected
- [ ] IP address updates after connection
- [ ] Library shows correct config count and filtering works
- [ ] Settings persist after app restart
- [ ] Add custom source adds configs to library

## Roadmap

### Phase 1 ✅ Complete
- Project setup with GetX + Hive
- Config models (WireGuard, OpenVPN, Shadowsocks)
- GitHub service with caching
- Config persistence

### Phase 2 ✅ Complete
- Speed/reliability testing in background
- Platform channels for VPN (Android/iOS)
- Connection state machine
- Home screen with one-tap connect

### Phase 3 ✅ Complete
- Library screen with filtering and sorting
- Settings screen with preferences
- Config details view
- Custom source management

### Phase 4 (Current)
- [ ] Full test suite (unit + integration + E2E)
- [ ] Polish animations and error handling
- [ ] GitHub release setup and APK builds
- [ ] V2 extensibility (V2Ray, Trojan, NaïveProxy prep)

### Phase 5 (Roadmap)
- Kill switch implementation
- Split tunneling
- DNS leak prevention
- In-app logging and debugging tools
- Dark mode polish
- Localization (8+ languages)

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
