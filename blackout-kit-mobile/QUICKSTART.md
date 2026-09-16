# Blackout Kit Mobile - Quick Start Guide

Get up and running with Blackout Kit Mobile in 5 minutes. 🚀

## For Users

### Installation

**Android:**
1. Download the APK from [GitHub Releases](https://github.com/blackout-kit/blackout-kit-mobile/releases)
2. Enable "Install from Unknown Sources" in Settings → Security
3. Tap the APK file to install

**iOS:**
1. Download the IPA from [GitHub Releases](https://github.com/blackout-kit/blackout-kit-mobile/releases)
2. Use Xcode or third-party tool to install on device

### First Run

1. **App Opens** → Fetches configs from hardcoded trusted repos (Mullvad, Windscribe, etc.)
2. **Wait for Tests** → App tests all configs for speed/reliability (~3-5 min)
3. **Home Screen** → Shows fastest working server
4. **Connect** → Tap big button to connect
5. **Check** → Verify IP changed at https://whatismyipaddress.com

### Add Custom VPN Sources

1. Go to **Settings** → **Repositories**
2. Tap **Add Repository**
3. Paste GitHub URL: `https://github.com/user/repo`
4. Confirm → App fetches new configs

### Troubleshooting

| Issue | Fix |
|-------|-----|
| App won't connect | Ensure you're connected to internet first |
| No configs found | Check Settings → Repositories, refresh manually |
| Connection slow | Try different server in Library screen |
| App crashes | Check Android/iOS logs: `adb logcat` or Xcode console |

---

## For Developers

### Setup (10 min)

**Prerequisites:**
```bash
# Check versions
flutter --version      # Should be 3.22+
dart --version         # Should be 3.0+
```

**Clone & Setup:**
```bash
# Clone repository
git clone https://github.com/blackout-kit/blackout-kit-mobile.git
cd blackout-kit-mobile

# Get dependencies
flutter pub get

# Run tests to verify setup
flutter test
```

### Development Workflow

**Run App (Debug):**
```bash
flutter run
```

**Hot Reload** (preserve state):
- Press `r` in terminal during `flutter run`

**Hot Restart** (clear state):
- Press `R` in terminal during `flutter run`

**Build Release:**
```bash
# Android APK
flutter build apk --release

# iOS IPA
flutter build ios --release --no-codesign
```

### Key Project Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, GetX setup |
| `lib/models/config.dart` | Config data model (WireGuard, OpenVPN, Shadowsocks) |
| `lib/services/github_service.dart` | Fetch configs from GitHub |
| `lib/services/config_service.dart` | Local config storage (Hive) |
| `lib/services/vpn_service.dart` | Platform channels for VPN |
| `lib/controllers/connection_controller.dart` | Connection state machine |
| `lib/screens/home_screen.dart` | Main UI (big connect button) |
| `lib/screens/library_screen.dart` | Config browser |
| `lib/screens/settings_screen.dart` | Settings & repositories |

### Common Tasks

**Add Protocol Support (e.g., V2Ray):**
1. Create `lib/models/v2ray_config.dart` extending `Config`
2. Implement `fromMap()` parser and `connect()` method
3. Register in `config_service.dart` factory
4. No UI changes needed! 🎉

**Run Tests:**
```bash
# All tests
flutter test

# Specific test file
flutter test test/models/config_test.dart

# With coverage
flutter test --coverage
```

**Debug on Real Device:**
```bash
# List devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# View logs
flutter logs
```

**Code Analysis:**
```bash
# Format code
flutter format lib/

# Check for issues
flutter analyze

# Upgrade dependencies
flutter pub upgrade
```

### Architecture Primer

The app uses these core patterns (full details in `ARCHITECTURE.md`):

1. **GetX** - State management with reactive observables (`.obs`)
2. **Hive** - Encrypted local storage for configs
3. **Platform Channels** - Native Android/iOS VPN integration
4. **Registry Pattern** - Engine discovery (prep for V2 extensibility)
5. **Factory Pattern** - Protocol-agnostic config parsing

**Data Flow:**
```
GitHub → Fetch Configs → Parse (factory) → Test (background) 
→ Store (Hive) → Filter/Sort → Display → Connect (platform channel)
```

### Testing Checklist

Before committing:
```bash
# 1. Run all tests
flutter test

# 2. Check code style
flutter analyze

# 3. Format code
flutter format lib/

# 4. Manual testing
flutter run
```

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes, commit atomically
git commit -m "feat: add feature description"

# Push to fork
git push origin feature/your-feature

# Open PR on GitHub
```

### IDE Setup

**Android Studio / IntelliJ:**
1. Install Flutter plugin from Marketplace
2. Configure Flutter SDK path (Settings → Languages → Flutter)
3. Create new Flutter project to verify

**VS Code:**
1. Install Dart and Flutter extensions
2. Open Command Palette → Flutter: New Project
3. Select this project folder

### Next Steps

- 📖 Read `ARCHITECTURE.md` for detailed design patterns
- 🤝 Check `CONTRIBUTING.md` for full guidelines
- 🔒 Review `SECURITY.md` for threat model
- 🐛 Open issue on GitHub if you find bugs
- 💡 Suggest features in GitHub Discussions

### Getting Help

- **GitHub Issues** - Report bugs and request features
- **GitHub Discussions** - Ask questions, discuss ideas
- **Security Issues** - Email security@blackout-kit.dev (private)

### Performance Tips

- **Speed tests** run in background isolate (don't freeze UI)
- **Use Obx()** only for reactive widgets (not every widget)
- **Profile with DevTools**: `flutter pub global run devtools`
- **Check widget tree**: Right-click in DevTools → Show Debug Paint

### Advanced Debugging

```bash
# Verbose logging
flutter run -v

# Attach debugger to running app
flutter attach

# View widget tree in real-time
flutter pub global run devtools
```

---

**Ready to code?** 🚀 Start with `flutter run` and explore the app!

For complete documentation, see [README.md](README.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [CONTRIBUTING.md](CONTRIBUTING.md).

**Questions?** Open a GitHub issue or check existing discussions. 😊
