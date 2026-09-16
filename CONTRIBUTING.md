# Contributing to Blackout Kit Mobile

Thank you for your interest in contributing! This document outlines how to get started, coding standards, and the contribution process.

## Getting Started

### Prerequisites
- Flutter 3.22+
- Dart 3.0+
- Android SDK 24+ (for Android development)
- Xcode 14+ (for iOS development)
- Git

### Setup
```bash
# Clone your fork
git clone https://github.com/<your-username>/blackout-kit-mobile.git
cd blackout-kit-mobile

# Get dependencies
flutter pub get

# Run tests to verify setup
flutter test
```

## Code Standards

### Dart Style Guide
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use `flutter format` to auto-format code: `flutter format lib/`
- Use `flutter analyze` to check for issues: `flutter analyze`

### Naming Conventions
| Element | Style | Example |
|---------|-------|---------|
| Classes | PascalCase | `ConfigService`, `HomePage` |
| Methods | camelCase | `loadConfigs()`, `testSpeed()` |
| Variables | camelCase | `isConnected`, `configList` |
| Constants | camelCase | `defaultTimeout`, `maxRetries` |
| Files | snake_case | `config_service.dart`, `home_page.dart` |

### Code Patterns
- **State Management**: Use GetX (Rx observables, controllers, bindings)
- **Persistence**: Use Hive for encrypted key-value storage
- **Services**: Keep business logic in GetX services, not widgets
- **Validation**: Validate at system boundaries (user input, external APIs)
- **Error Handling**: Use ErrorHandler service for consistent error messages

## Architecture Overview

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed patterns.

**Key Design Decisions:**
1. **Registry Pattern** - Engine discovery for V2 extensibility
2. **Factory Pattern** - Protocol-agnostic config parsing
3. **State Machine** - Controlled VPN connection lifecycle
4. **Atomic Persistence** - Safe config storage with Hive

## Adding a New Feature

### Example: Add V2Ray Support (V2 Feature)

**Step 1**: Create config model
```dart
// lib/models/config.dart
class V2RayConfig extends Config {
  final String vmessId;
  final String alterId;
  
  @override
  String get protocol => 'v2ray';
  
  @override
  Future<bool> connect() async {
    return await vpnService.connect(
      protocol: 'v2ray',
      displayName: displayName,
      // ... protocol-specific params
    );
  }
}
```

**Step 2**: Register in factory
```dart
// lib/services/config_service.dart
case 'v2ray':
  return V2RayConfig.fromMap(map);
```

**Step 3**: Write tests
```dart
// test/models/v2ray_config_test.dart
test('V2RayConfig parses VMESS URI', () {
  // Test parsing and validation
});
```

**Step 4**: UI automatically picks it up
- Library screen: filter by protocol ✓
- Settings: protocol dropdown ✓
- Home screen: fastest selector ✓

**No UI changes needed!**

## Testing

### Unit Tests
```bash
# Test specific file
flutter test test/models/config_test.dart

# Test all models
flutter test test/models/

# Test with coverage
flutter test --coverage
```

### Integration Tests
```bash
flutter test integration_test/app_flow_test.dart
```

### What to Test
- Config parsing and validation
- Deduplication by hash
- Service methods (GitHub API, speed ranking)
- Controller state transitions
- Error handling

## Commit Guidelines

### Format
```
type: brief description

Longer explanation if needed. Reference issues like "Closes #123" if applicable.

Co-authored-by: Name <email@example.com> (if pair programming)
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code reorganization (no behavior change)
- `test`: Test additions/changes
- `chore`: Build, dependency updates

### Examples
```
feat: add V2Ray protocol support

Implements V2RayConfig extending Config model with support for VMESS URI parsing.
Registry pattern allows seamless UI integration without UI changes.
Closes #42

fix: handle GitHub rate limiting gracefully

Add 1-hour cache TTL to avoid hitting 60 req/hour limit. Displays user-friendly
message when rate limited. Tests added for cache validation.

test: add ConfigService integration tests

Tests full flow: save → load → deduplicate for each protocol.
Covers edge cases: empty list, concurrent saves, invalid formats.
```

## Pull Request Process

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature`
3. **Make changes** and commit atomically
4. **Add tests** for new functionality
5. **Run tests locally**: `flutter test`
6. **Push to your fork**: `git push origin feature/your-feature`
7. **Open a PR** with clear description

### PR Checklist
- [ ] Tests added/updated
- [ ] Code formatted (`flutter format`)
- [ ] No linting issues (`flutter analyze`)
- [ ] Follows architecture patterns (see ARCHITECTURE.md)
- [ ] Documentation updated if needed
- [ ] Commit messages clear and descriptive

### Code Review
- Reviewer will check:
  - Adherence to patterns and standards
  - Test coverage
  - Edge case handling
  - Performance implications
- Address feedback promptly
- Squash commits if requested

## Common Tasks

### Running the App
```bash
# Debug build
flutter run

# Release build (optimized)
flutter run --release

# Specific device
flutter run -d <device-id>
```

### Building for Release
```bash
# Android APK
flutter build apk --release

# iOS IPA
flutter build ios --release --no-codesign
```

### Debugging
```bash
# Hot reload (preserve state)
flutter run

# Hot restart (clear state)
# Press 'R' in terminal during flutter run

# Verbose logging
flutter run -v

# Attach debugger to running app
flutter attach
```

## Documentation

- **README.md**: User-facing overview and setup
- **ARCHITECTURE.md**: Design patterns and extensibility
- **CONTRIBUTING.md**: This file - contribution guidelines
- **Code comments**: Only add WHY (not WHAT), one line max

### Updating Docs
When you change behavior:
1. Update relevant `.md` file
2. Update code comments if logic is non-obvious
3. Include in PR description

## Questions & Support

- **GitHub Issues**: Report bugs and feature requests
- **GitHub Discussions**: Ask questions and discuss ideas
- **Security Issues**: Email security@blackout-kit.dev (DO NOT open public issue)

## Development Tips

### Performance
- Speed tests run in background isolate (non-blocking)
- Use Obx() only for reactive UI (not every widget)
- Profile with DevTools: `flutter pub global run devtools`

### Debugging
- Check logs: `flutter logs`
- View widget tree: Right-click in DevTools → Show Debug Paint
- Use breakpoints in VS Code or Android Studio

### Common Issues
| Issue | Solution |
|-------|----------|
| `pub get` fails | Run `flutter pub upgrade` |
| Tests fail | Clear cache: `flutter clean && flutter pub get` |
| Hot reload issues | Use hot restart (R key) or restart app |
| Platform channel error | Check native code paths (iOS/Android) |

## Recognition

Contributors are recognized in:
- README.md acknowledgments section
- GitHub releases for each version
- Project history

---

**Thank you for contributing! Your work helps make Blackout Kit Mobile a trustworthy VPN app for everyone.** 🚀
