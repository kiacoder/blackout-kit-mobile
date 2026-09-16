# Blackout Kit Mobile - Architecture Guide

This document explains the design patterns and extensibility strategy for Blackout Kit Mobile.

## Core Principles

1. **Config-Based, Not Code-Based**: All VPN configs come from external sources (GitHub), not hardcoded
2. **Extensibility from Day 1**: Designed to scale to V2 (Blackout Kit engines) and V3 (reverse-engineered Hotspot Shield) without major redesign
3. **Safety-Critical**: No backend API exposure; all trust is explicit and transparent
4. **Replicate CLI Patterns**: Use the same architectural patterns as Blackout Kit CLI for consistency

## Architectural Patterns

### 1. Registry Pattern (V2 Extensibility)

**Location**: `lib/models/engine_capability.dart`

The Registry pattern allows new VPN engines to register themselves at runtime, enabling V2 extensibility:

```dart
// V2 engines register like this
EngineRegistry.register('v2ray', V2RayConfig);
EngineRegistry.register('trojan', TrojanConfig);

// UI automatically discovers them
final engine = EngineRegistry.getEngine('v2ray');
```

**Why**: Allows adding V2Ray, Trojan, NaïveProxy without UI changes. Future releases can drop in new engines.

### 2. Factory Pattern

**Location**: `lib/services/config_service.dart` → `_configFromMap()`

Converts serialized config maps to protocol-specific classes:

```dart
Config _configFromMap(Map<String, dynamic> map) {
  switch (map['protocol']) {
    case 'wireguard':
      return WireGuardConfig.fromMap(map);
    case 'openvpn':
      return OpenVPNConfig.fromMap(map);
    case 'shadowsocks':
      return ShadowsocksConfig.fromMap(map);
    // V2 engines get loaded here automatically
    default:
      throw Exception('Unknown protocol: ${map['protocol']}');
  }
}
```

**Why**: Protocol-agnostic deserialization. Adding protocols just adds a case.

### 3. Abstract Base Class (Config Model)

**Location**: `lib/models/config.dart`

```dart
abstract class Config {
  String get displayName;
  String get address;
  int get port;
  String get protocol; // "wireguard", "openvpn", "v2ray", etc.
  String get rawUri;

  String getHash(); // SHA256 for deduplication
  Future<bool> connect();
  Future<void> disconnect();
  Map<String, dynamic> toMap();
}
```

**Why**: Protocol-agnostic interface. UI works with any Config subclass.

### 4. Atomic Persistence

**Location**: `lib/services/config_service.dart` → `saveConfig()`

Hive handles atomic writes internally:

```dart
// Hive writes to temp file first, then atomic rename
await _configBox.put(configHash, config.toMap());
```

**Why**: Prevents corruption if app crashes mid-write.

### 5. State Machine Pattern

**Location**: `lib/controllers/connection_controller.dart`

```dart
enum ConnectionState {
  idle,
  selecting,
  connecting,
  connected,
  testing,
  disconnecting,
  error,
}
```

Transitions:
- `idle` → `connecting` (user taps connect)
- `connecting` → `connected` (success) or `error` (failure)
- `connected` → `disconnecting` (user taps disconnect)
- `disconnecting` → `idle`

**Why**: Prevents invalid state transitions (can't disconnect if not connected).

### 6. Dependency Injection (GetX Services)

**Location**: `lib/main.dart`

```dart
Get.put<ConfigService>(configService);
Get.put<ConnectionController>(connectionController);

// In any screen/controller
final controller = Get.find<ConnectionController>();
```

**Why**: Loose coupling, easy testing (mock GetX dependencies).

### 7. GitHub Integration (Caching + TTL)

**Location**: `lib/services/github_service.dart`

```dart
// Check cache first
if (_contentCache.containsKey(url)) {
  final cached = _contentCache[url]!;
  if (DateTime.now().difference(cached['timestamp']).inHours < 1) {
    return cached['content'];
  }
}

// Fetch from GitHub API
final response = await http.get(...);
_contentCache[url] = {'content': data, 'timestamp': DateTime.now()};
```

**Why**: Avoids GitHub rate limiting (60 req/hr for anonymous). Respects user bandwidth.

### 8. Reactive State Management (GetX .obs)

**Location**: All controllers

```dart
final RxList<Config> allConfigs = RxList<Config>();
final RxString filterProtocol = RxString('all');
final RxBool isConnected = RxBool(false);

// UI updates automatically on change
Obx(() => Text('Configs: ${allConfigs.length}'))
```

**Why**: Simple, performant. No boilerplate vs Provider.

## Data Flow

### Fetch → Test → Connect

```
1. User launches app
   ↓
2. ConfigController.loadSources() [trusted repos + custom]
   ↓
3. GitHubService.fetchConfigsFromSource() [cache check → GitHub API]
   ↓
4. ConfigService.saveConfigs() [dedup by hash → Hive storage]
   ↓
5. User taps Connect or ConnectFastest
   ↓
6. TesterService.testConfigs() [speed/latency in background isolate]
   ↓
7. ConnectionController.connect(fastestConfig)
   ↓
8. VPNService.connect() [platform channel → Android/iOS native]
```

## Extension Points (V2, V3)

### Adding a New Protocol (V2Ray Example)

**Step 1**: Create config model
```dart
// lib/models/config.dart - add to file
class V2RayConfig extends Config {
  final String vmessId;
  final String alterId;
  final String security;

  @override
  String get protocol => 'v2ray';

  @override
  String getHash() => sha256.convert(utf8.encode(rawUri)).toString();

  @override
  Future<bool> connect() async {
    return await vpnService.connect(
      protocol: 'v2ray',
      displayName: displayName,
      address: address,
      port: port,
      rawUri: rawUri,
      vmessId: vmessId,
      alterId: alterId,
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

**Step 3**: Register in engine registry
```dart
// lib/models/engine_capability.dart
EngineRegistry.register('v2ray', V2RayConfig);
```

**Step 4**: UI automatically picks it up in:
- Library screen (filter by protocol)
- Settings (preferred protocol dropdown)
- Home screen (quick stats, fastest selector)

**No UI changes needed.**

### Adding VPN Engine from External Package (V2 Engines)

```dart
// V2 engine as separate package
import 'package:blackout_kit_engines/v2_engines.dart';

// In main.dart, after GetX setup
V2Engines.register(); // Registers V2Ray, Trojan, NaïveProxy automatically

// All 3 engines now available everywhere
final engine = EngineRegistry.getEngine('trojan');
```

### Adding Hotspot Shield Reverse-Engineered (V3 Engine)

```dart
// In main.dart
HotspotShieldEngine.initialize();
HotspotShieldEngine.register();

// Now HotspotShield configs appear in Library
// alongside WireGuard, OpenVPN, Shadowsocks, etc.
```

## Testing Strategy

### Unit Tests
- **Config models**: Parse valid/invalid URIs, deduplication
- **Services**: GitHub caching, ranking logic, reliability calculation
- **Controllers**: State transitions, observable updates

```bash
flutter test test/models/
flutter test test/services/
```

### Integration Tests
- Full flow: fetch → test → connect
- Platform channel calls (mock native)
- UI navigation between screens

```bash
flutter test integration_test/app_flow_test.dart
```

### E2E Tests
- Real device with real VPN configs
- Verify actual IP changes
- Check for DNS/WebRTC leaks
- Test kill switch behavior

## Performance Considerations

### Memory
- **Config storage**: ~5KB per config × 100 = 500KB Hive storage
- **Test results**: ~200B per config × 100 = 20KB in memory
- **Total**: <10MB app footprint expected

### Network
- **GitHub API**: 60 req/hour (anonymous). With caching (1-hour TTL), sustainable
- **Speed tests**: Configurable intervals (default 60 min). Can be disabled

### UI
- **Speed tests run in background isolate**: Non-blocking
- **Large config lists**: Use ListView with lazy loading (not implemented yet)
- **Animations**: Subtle, low cost (connect button gradient pulse)

## Security & Privacy

### What We Trust
- ✅ GitHub repositories (read-only, transparent)
- ✅ VPN server IP/port (public, verifiable)
- ✅ User-added custom sources (explicit trust)

### What We Don't Trust
- ❌ VPN provider's privacy claims (they see all traffic)
- ❌ Third-party packages (code review before adding)
- ❌ Closed-source binaries (all code is open-source)

### Data Handling
- Configs stored encrypted in Hive (device-specific key)
- No telemetry or analytics (optional, local only)
- No account creation (all local)
- Speed tests never send metadata to Blackout Kit

## Future Roadmap

### V2 (Blackout Kit Engines)
- Internal Blackout Kit V2Ray, Trojan, NaïveProxy implementations
- Drop-in replacement for GitHub-based configs
- Full control over engine behavior

### V3 (Hotspot Shield Reverse-Engineered)
- Reverse-engineered Hotspot Shield protocol
- Ultra-fast connection (proprietary optimization)
- All Hotspot Shield features without their app

### Phase 5
- Kill switch with iptables (Android) / PF (iOS)
- Split tunneling per-app
- DNS leak prevention (secure DNS)
- Improved UI/UX, animations
- Localization (8+ languages)

## Contributing to Architecture

When adding new features:

1. **Follow existing patterns** (Registry, Factory, State Machine)
2. **Extend, don't modify** (Add new Config subclass, don't modify Config base)
3. **Keep UI decoupled** (Controllers drive state, screens consume it)
4. **Test new additions** (Unit tests required for business logic)
5. **Document in ARCHITECTURE.md** (How to use the new extension)

## Questions?

Open a GitHub issue with tag `[architecture]` or email contributors@blackout-kit.dev
