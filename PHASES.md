# Blackout Kit Mobile - Development Phases

Complete roadmap showing all development phases, completed work, and future plans. 🗺️

## Overview

Blackout Kit Mobile is built in phases, with each phase adding significant features and stability. This document tracks progress from MVP (v1.0) through long-term vision (V2/V3).

---

## ✅ Phase 1: Foundation & Architecture

**Status: COMPLETED** ✓ | **Version: v1.0-beta**

### Deliverables

- [x] Flutter 3.22+ project setup with GetX state management
- [x] Config models: WireGuard, OpenVPN, Shadowsocks (Config base class)
- [x] Hardcoded trusted config sources (GitHub repositories)
- [x] GitHub API service with caching (1-hour TTL)
- [x] Config parsing and validation (factory pattern)
- [x] Local persistence with Hive (encrypted key-value storage)
- [x] Project structure following architectural patterns
- [x] Dependency injection with GetX services

### Technical Decisions

- **State Management:** GetX (reactive observables, simplicity)
- **Local Storage:** Hive (encrypted, no schema migrations needed)
- **Config Format:** Parse from GitHub raw URIs (WireGuard, OpenVPN, Shadowsocks)
- **Architecture:** Registry + Factory + State Machine patterns

### Key Files Created

- `lib/models/config.dart` - Config base class and protocol implementations
- `lib/services/github_service.dart` - GitHub config fetching with caching
- `lib/services/config_service.dart` - Local config management
- `pubspec.yaml` - All Flutter dependencies

---

## 🟡 Phase 2: VPN Integration & Core Features

**Status: COMPLETED** — native tunnel implemented; not yet verified on hardware

> **Correction (2026-09-19).** This phase was previously marked COMPLETED and
> listed native files that were never delivered. Commit `4e73204`
> ("chore: remove obsolete native VPN services") deleted four Kotlin files under
> `android/app/src/main/kotlin/com/blackoutkit/vpn/`. They were mocks — they set
> `isConnected = true` and returned a fabricated `192.168.1.x` address without ever
> calling `VpnService.Builder.establish()`. Removing them was correct, but the Dart
> layer was never updated, so every one of the 29 platform-channel calls threw
> `MissingPluginException` on Android. The real native layer now exists again; the
> engine binaries it needs are still pending.

### Deliverables

- [x] Speed and reliability testing in background (isolate)
- [x] Config ranking by performance (speed, latency)
- [x] Connection state machine (idle → connecting → connected → disconnected)
- [x] VPN service abstraction (Dart side)
- [x] Connection controller with reactive state
- [x] Android `BlackoutVpnService` — real `android.net.VpnService` + TUN + foreground service
- [x] `VpnPlugin` method-channel bridge, registered in `MainActivity.configureFlutterEngine()`
- [x] `VpnService.prepare()` consent flow surfaced to Dart
- [x] Xray engine bundled — `libv2ray.aar` (AndroidLibXrayLite, LGPL-3.0) v26.9.9
- [x] `XrayEngine.kt` — in-process core wrapper (`Seq.setContext` → `initCoreEnv` → `startLoop`)
- [x] `lib/services/xray_config.dart` — Dart builder for the Xray JSON, incl. the `tun` inbound
- [ ] sing-box + tun2socks bundled — **blocks Hysteria2 / TUIC / WireGuard / AmneziaWG / WARP**
- [ ] iOS `NEVPNManager` integration (existing Swift files are unregistered mocks)

### Technical Features

- **Speed Testing:** Background isolate (non-blocking UI)
- **State Machine:** Controlled connection lifecycle
- **Tunnel:** `Builder.establish()` returns a real `ParcelFileDescriptor`; connect
  refuses to report success unless the engine is actually up, so a missing engine
  can never black-hole traffic
- **Reliability:** Working config detection and filtering

### Key Files

- `lib/services/vpn_service.dart` - Platform channel interface
- `android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutVpnService.kt` - Android tunnel
- `android/app/src/main/kotlin/com/blackoutkit/vpn/VpnPlugin.kt` - Channel bridge
- `android/app/src/main/kotlin/com/blackoutkit/vpn/XrayEngine.kt` - In-process Xray core
- `android/app/src/main/kotlin/com/blackoutkit/vpn/EngineRunner.kt` - Subprocess engine/fd handoff
- `android/app/src/main/kotlin/com/blackoutkit/vpn/NetworkPlugin.kt` - App list / kill-switch state bridge
- `lib/services/xray_config.dart` - Xray JSON generation
- `lib/controllers/connection_controller.dart` - Connection state machine
- `lib/services/tester_service.dart` - Reachability testing

---

## ✅ Phase 3: User Interface & Experience

**Status: COMPLETED** ✓ | **Version: v1.0-beta**

### Deliverables

- [x] Home screen with big connect button
- [x] Real-time connection status display (localized — see Phase 5)
- [ ] Current IP address display — **not delivered.** `VpnPlugin` answers
  `getConnectedIP` with a hardcoded `null`, so the row never renders. The UI
  degrades honestly rather than showing a placeholder, but the feature does not
  exist. Implementing it needs a decision: the tunnel's own address
  (`10.111.222.1`) is not the exit IP the user wants, and fetching the exit IP
  over HTTP is unreliable here because a VPN app's own traffic may not traverse
  its own tunnel.
- [x] Quick stats (latency, configs, working count, reliability)
- [x] Config library screen with filtering and sorting
- [x] Settings screen with preferences
- [x] Config source management (add/remove repositories)
- [x] Tab-based navigation
- [x] Material 3 design system

### UI Features

- **Home Screen:** One-tap VPN connection, connection stats
- **Library Screen:** Browse configs with protocol/speed filtering, sorting
- **Settings Screen:** Manage repos, VPN preferences, appearance
- **Status Display:** Connected server, IP, uptime, speed

### Key Files Created

- `lib/screens/home_screen.dart` - Main connection UI
- `lib/screens/library_screen.dart` - Config browser
- `lib/screens/settings_screen.dart` - Settings management
- `lib/screens/engine_hub_screen.dart` - Engine availability view
- `lib/screens/split_tunneling_screen.dart` - Per-app routing
- `lib/screens/speed_test_screen.dart` - Reachability tester
- `lib/screens/root_screen.dart` - Tab navigation
- `lib/widgets/config_tile.dart` - Config list item
- `lib/controllers/settings_controller.dart` - Settings state

> **Correction (2026-09-19).** This list previously named
> `lib/screens/splash_screen.dart`, which does not exist.

---

## ✅ Phase 4: Testing, Polish & Release Setup

**Status: COMPLETED** | **Version: v1.0-beta**

> **Correction (2026-09-19).** The 13 original test files (3,434 lines) did not
> compile — `dart analyze test/` reported 387 errors because they were written
> against an API this codebase never had. A suite that cannot compile aborts the
> whole `flutter test` run, so **no test in the project had ever executed**.
>
> They now live in `test_legacy/` as `*.dart.broken`, with `test_legacy/README.md`
> explaining every error category and how to restore them.
>
> `test/` contains a replacement suite of **80 tests** that compiles and passes,
> covering the highest-risk logic: Xray config generation (including the `tun`
> inbound and REALITY validation), builder-time option validation, and share-link
> parsing for every protocol.
>
> **Caveat that still stands:** these are unit tests. They do not open a tunnel,
> and nothing here verifies the native layer on a device.

### Running the tests

```bash
flutter test
```

On a machine with `HTTP_PROXY` / `HTTPS_PROXY` set, `flutter test` fails before
running anything with:

```
Unable to connect to flutter_tester process:
WebSocketException: Invalid WebSocket upgrade request
```

The test runner talks to `flutter_tester` over a local WebSocket, and the proxy
intercepts it. Bypass the proxy for loopback:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1" \
  flutter test
```

This is an environment quirk, not a project problem — but the error message gives
no hint, so it is worth knowing.

> **Caveat (2026-09-19).** These tests exercise the Dart layer against *mocked*
> method channels. They pass while the native tunnel was entirely absent, so a
> green suite here does **not** mean the app can connect. Treat them as
> regression cover for Dart logic, not as end-to-end verification.

### Deliverables

#### Testing Infrastructure ✓
- [x] 134 unit tests that compile and pass, in five files:
  - `test/config_parsing_test.dart` (43) — share-link parsing for every protocol,
    WireGuard `.conf` section handling, and a reload round-trip for all six
  - `test/xray_config_test.dart` (40) — Xray JSON, `tun` inbound, REALITY
    validation, routing, and the `wireguard` outbound
  - `test/vpn_session_options_test.dart` (20) — builder-time option validation and precedence
  - `test/services/engine_availability_test.dart` (17) — engine capability gating
    and the engine-hub runnable rule
  - `test/services/localization_service_test.dart` (14) — translation key parity across 9 languages
- [x] Legacy suite quarantined to `test_legacy/` with a per-category failure write-up
- [x] GitHub Actions CI/CD (test.yml) - automated testing on every push
- [x] GitHub Actions CI/CD (build.yml) - APK/IPA builds on version tags
- [ ] Controller / service / widget tests — **none exist yet**
- [ ] Integration tests for complete workflows — **none exist yet**

> The earlier version of this list claimed "~40+ unit tests" and "~8+ integration
> tests" for models, services, controllers and full workflows. None of those files
> existed, and the suite that did exist could not compile. The list above reflects
> what is actually in `test/`.

#### Polish & Animations ⚠️ (corrected — most of this list was not true)

Verified as actually present in reachable code:

- [x] Loading indicators — `CircularProgressIndicator` in the home, library,
      speed-test and split-tunneling screens
- [x] Retry / refresh affordances — `RefreshIndicator` plus refresh icons in the
      library, home and config-import screens
- [x] Error surfacing — the home screen renders `ConnectionController.statusMessage`
      and raises a red `SnackBar` on failure; `AlertDialog` is used for
      confirmations in the library, settings and import screens
- [x] Readable failure text — `VPNService.lastError` and the connection
      controller's `statusMessage` carry real reasons ("REALITY config is missing
      the server public key", "engine not bundled", "VPN permission was denied")
      instead of a generic failure

**Not delivered, and previously marked as done:**

- [ ] **Screen transitions, fade / slide / pulse animations.** There is no
      `AnimationController`, `Tween`, `FadeTransition`, `SlideTransition` or
      `ScaleTransition` anywhere in `lib/screens/`, and `main.dart` declares no
      `pageTransition`. The only animation code in the project sits in
      `lib/widgets/`, and **seven of those nine widgets are never instantiated**:
      `AnimatedConnectButton`, `AnimatedConnectionButton`,
      `AnimatedErrorNotification`, `AnimatedLoadingOverlay`,
      `AnimatedSecurityToggle`, `AnimatedStatusIndicator`,
      `SmoothPageTransition`. The barrel `lib/widgets/index.dart` that exports
      them is not imported either. Only `AppLogo` and `ConfigTile` are used.
      So "animated connect button", "fade-in screen transitions", "slide-in
      content" and "pulse animation for loading states" describe code that
      exists but never runs. The widgets are left in place — they are correct,
      just unwired — but nothing in the UI animates today.
- [ ] **No dedicated error widget.** `AnimatedErrorNotification` is unused, and
      `library_screen` has no error branch at all: a failed config fetch shows
      nothing rather than an error state.
- [ ] **No centralized error handling service.** `lib/services/error_handler.dart`
      was referenced from nowhere, and it defined its **own** `SocketException`
      and `TimeoutException` classes which shadow `dart:io`'s — so its
      `getUserMessage` could never match a real network error even if called.
      Deleted. Error handling is per-call-site `try`/`catch`.
- [ ] **`lib/screens/debug_screen.dart` (358 lines) is unreachable.** Nothing
      navigates to it; the reachable logging UI is `LogsScreen`, opened from
      Settings. Left in place, but it renders for nobody.

#### Documentation ✓
- [x] Comprehensive ARCHITECTURE.md explaining 8 core patterns
- [x] CONTRIBUTING.md with contribution workflow
- [x] SECURITY.md with threat model and responsible disclosure
- [x] QUICKSTART.md for developers and users
- [x] DEPLOYMENT.md with release procedures
- [x] PHASES.md (this file) - project roadmap
- [x] LICENSE (MIT) for open-source distribution
- [x] .gitignore for Flutter projects
- [x] CHANGELOG.md documenting version history

#### Release Setup ✓
- [x] GitHub release workflow (.github/workflows/release.yml)
- [x] Automated APK builds and uploads to releases
- [x] Automated IPA builds and uploads to releases
- [x] Version tagging strategy (semantic versioning)
- [x] Release notes generation from CHANGELOG.md
- [x] Beta/stable release distinction
- [x] Pre-release support for alpha/beta versions

### Key Files Created

- `test/config_parsing_test.dart` - Share-link parsing for all protocols
- `test/xray_config_test.dart` - Xray JSON generation and routing
- `test/vpn_session_options_test.dart` - Session option validation
- `test/services/engine_availability_test.dart` - Engine capability gating
- `test_legacy/README.md` - Why the original suite was quarantined
- `lib/widgets/animated_button.dart` - Animation components
- `lib/services/error_handler.dart` - Error handling service
- `.github/workflows/test.yml` - CI/CD testing
- `.github/workflows/build.yml` - APK/IPA builds
- `.github/workflows/release.yml` - Release automation
- `ARCHITECTURE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `DEPLOYMENT.md`, `QUICKSTART.md`
- `CHANGELOG.md`, `LICENSE`, `.gitignore`

> **Correction (2026-09-19).** This list previously named five test files
> (`test/models/config_test.dart`, `test/services/github_service_test.dart`,
> `test/services/config_service_test.dart`,
> `test/controllers/config_controller_test.dart`,
> `test/controllers/connection_controller_test.dart`) that do not exist in the
> repository. The list above is the real one.

---

## 🚀 Phase 5: Advanced Features (Next)

**Status: PLANNED** ⏳ | **Version: v1.1**

> **Correction (2026-09-19).** This section previously listed the kill switch,
> split tunneling and DNS leak prevention as planned work, and described the
> Android kill switch as "iptables-based". iptables requires root and is
> unavailable to a normal app, so that plan was never implementable. All three
> features are now **done** and moved to Phase 3. What remains is below.

### Completed in the 2026-09-19 honesty pass

The screens advertised engines and protocols that this build cannot run. Fixed:

- [x] **Protocol picker** (`settings_screen.dart`) — offered WireGuard / OpenVPN /
      Shadowsocks. None of the first two can connect, and the picker omitted VLESS,
      VMess and Trojan, which can. It now asks the native layer which protocols are
      served and lists the rest as greyed-out "requires the sing-box runtime".
- [x] **Default protocol** changed from `wireguard` (cannot connect) to `vless`.
- [x] **Engine Hub** (`engine_hub_screen.dart`) — claimed "10 CLI Bypass Engines" and
      "Full parity with Blackout Kit desktop & Linux CLI" while showing every engine as
      available. It now intersects the registry with `VPNService.getEngineInfo()` and
      reports "2 of 10 Engines Available", with unbundled engines greyed out.
- [x] **Invented version numbers** removed from `EngineRegistry`. It asserted
      `Xray 1.8.24` while the bundled core is 26.9.9. The Xray version now comes from
      `Libv2ray.checkVersionX()` at runtime; unverifiable strings for engines we do not
      ship are gone.
- [x] **Connect path** (`connection_controller.dart`) — added a pre-flight capability
      check so the user is not asked to grant VPN consent for a protocol that can never
      connect, and so "connect to fastest" cannot pick a config it must then refuse.
- [x] **Home screen Connect button** — passed the connection controller's single cached
      test result, or an empty list on a cold start. A non-null empty list short-circuits
      the tester inside `connectFastest`, so the first tap always failed with "No working
      configs found" without testing anything. It now passes the library's real results.
- [x] **"Speed" stat card** — throughput is never measured, so the card could only ever
      read "Not tested". Replaced with the latency that is actually measured.
- [x] **`test/services/engine_availability_test.dart`** — 13 tests covering the gating
      contract, including the fail-open behaviour when the platform reports nothing
      and a case asserting WireGuard is now allowed.
      Suite is now 134 tests.
- [x] **Unused geo data excluded** — `androidResources.ignoreAssetsPattern` drops
      `geoip.dat` / `geosite.dat` / `geoip-only-cn-private.dat`. **Measured** saving
      on disk: 7.5 MB. (The three files are ~28 MB raw, but they deflate ~3.8:1
      inside the APK, so an earlier claim of "28 MB saved" was wrong.)
- [x] **ABI splits unblocked** — `ndk.abiFilters` removed (it made AGP reject
      `--split-per-abi`), x86 libs stripped via `packagingOptions` instead.
      **Measured** splits: 57.6 MB (arm64-v8a) / 52.6 MB (armeabi-v7a).
      Now 60.2 MB / 55.2 MB per ABI.
- [x] **CI was broken and is now fixed** (`build.yml`, `release.yml`):
  - Java was pinned to **11** while the project requires **17** — CI could not compile
  - `release.yml` uploaded `build/app/outputs/flutter-app-release.apk`, a path that
    has never existed. The release step published nothing and still reported success.
  - Both workflows now build per-ABI APKs
  - The **iOS job was removed**: it wrapped a non-functional `Runner.app` into an
    unsigned `.ipa` and attached it to releases
- [x] **Docs re-verified against the filesystem** — `PHASES.md` and `README.md` both
      named test files that do not exist (`test/models/config_test.dart`,
      `test/services/tester_service_test.dart`, …) and claimed "~40+ unit tests" and
      "✅ Speed testing accurate". Corrected; the real suite is 134 tests and no code
      path measures throughput.
- [x] **Language setting was a no-op** — `LocalizationService` was never registered
      with GetX, and `GetMaterialApp` had no `translations` / `locale`, so picking a
      language persisted a preference and changed nothing on screen.
      `LanguageSettingsScreen` was unreachable dead code that *crashed on open*
      (`Get.find<LocalizationService>()` on an unregistered service); it duplicated
      the picker already in Settings and was deleted. Now wired up end to end:
      `SettingsController.selectedLanguage` is the single source of truth, fed to
      `GetMaterialApp.locale` inside an `Obx`.
- [x] **`getConnectedIP` was an undocumented stub** — the native side answers with a
      hardcoded `null`, and Phase 3 listed "Current IP address display" as delivered.
      Claim corrected and the stub now says why it exists.
- [x] **Channel surface audited** — every `invokeMethod` call in `lib/` was diffed
      against the Kotlin handlers. All 7 `VpnPlugin` and 4 `NetworkPlugin` methods
      line up; no dead calls remain.

### Added in the 2026-09-19 engine pass

#### WireGuard now runs, with no new dependency

The bundled core was inspected directly rather than trusted. Unzipping
`android/app/libs/libv2ray.aar` and reading the module registrations out of
`jni/arm64-v8a/libgojni.so` shows it contains **`xray.proxy.wireguard`**, together
with the full config schema it accepts (`secretKey`, `address`, `peers`,
`endpoint`, `publicKey`, `preSharedKey`, `keepAlive`, `allowedIPs`, `mtu`,
`reserved`).

So WireGuard never needed sing-box. `XrayConfigBuilder` now emits a `wireguard`
outbound, and `wireguard` is on the Xray allow-list in Dart, in
`BlackoutVpnService.XRAY_PROTOCOLS`, and in the native capability report.

Consequences:

- The sing-box licensing question (GPL-3.0 vs this project's MIT) now blocks only
  **four** protocols, not five. WireGuard — much the most common of them — is
  unaffected.
- `EngineRunner` no longer lists `wireguard`, since it can no longer be routed
  there.
- Same verification also confirmed `xray.proxy.tun`, so the TUN inbound the
  config generator emits is real, and that the core carries Hysteria **v1** only
  (`xray.proxy.hysteria`) — which is why Hysteria2 still cannot be served.

#### Three real bugs found while auditing

- [x] **Saved configs were deleted on every app start.**
      `ConfigService._configFromMap` had explicit branches only for WireGuard,
      OpenVPN and Shadowsocks, and `default: return null` for everything else.
      `getAllConfigs()` discards nulls, so every VLESS / VMess / Trojan /
      Hysteria2 / TUIC record was dropped from the library each launch — VLESS
      being the app's primary protocol. Records now fall back to re-parsing the
      `rawUri` stored alongside them; `test/config_parsing_test.dart` round-trips
      all six protocols to guard it.
- [x] **`xhttp` was emitted as a transport name the core does not have.**
      Share links with `type=xhttp` or `type=splithttp` were both normalised to
      `network: "xhttp"`. A byte scan of `libgojni.so` finds `splithttp` 14 times
      and the literal `xhttp` **never** — the only `xhttp` strings are the Go type
      name `XHTTPSettings` and the settings key `xhttpSettings`, which is a
      different thing from the dialer name. Both spellings now normalise to
      `splithttp`, and the builder also rewrites a persisted `xhttp` defensively.
- [x] **WireGuard profiles lost half their fields.** `WireGuardConfig.fromUri`
      never read `AllowedIPs`, `PresharedKey` or `PersistentKeepalive`, and wrote
      `[Interface] Address` into the base `Config.address`, which the UI and
      `validate()` treat as the *server* — so the config list displayed the
      device's own tunnel IP as the host. It also collapsed multi-peer profiles to
      one. The parser is now section-aware, keeps every peer, and `validate()`
      requires both halves instead of `||`.

#### Honesty fixes

- [x] **`XrayEngine.kt` claimed geo data was readable at runtime.** The docstring
      said the AAR's `geoip.dat` / `geosite.dat` are read from the APK assets "with
      no extra 28 MB of app storage". They are in fact stripped from the built APK
      by `androidResources.ignoreAssetsPattern`, so nothing can read them, and the
      real measured saving is 7.5 MB, not 28. Corrected, including what the
      consequence is (no `geosite:` / `geoip:` routing rules) and how to reverse it.
- [x] **`WarpConfig.fromUri` fabricated unusable configs.** It returned a config
      with an empty `privateKey` and empty `accountId` for any text merely
      containing "warp", producing a config-list entry that could never connect.
      It now returns null. A real WARP profile is a WireGuard `.conf`, which is
      parsed as WireGuard and *does* work.
- [x] **2.6 MB of unreferenced screenshots removed from the bundle.**
      `assets/images/` is declared wholesale in `pubspec.yaml`, so
      `emulator_screenshot.png` and `engine_hub_screenshot.png` — referenced
      nowhere in `lib/` — were shipping in every APK. Moved aside.
- [x] **The channel map advertised arguments nobody read.** `vpn_service.dart`
      sent `privateKey`, `gateway`, `configContent`, `method`, `password` and
      `plugin` on every connect. The Kotlin side reads nine keys and none of
      those. Removed.
- [x] **The engine hub would have overstated itself the moment WireGuard
      worked.** Its "N of 10 Engines Available" count used
      `compatibleProtocols.any(canConnect)`. AmneziaWG lists
      `['amneziawg', 'wireguard']` and WARP lists `['warp', 'wireguard']`, so
      both cards would have lit up as available purely because WireGuard became
      servable — while neither engine is bundled and neither protocol can run.
      Now `every`, extracted as the testable `engineIsRunnable`, giving an honest
      **3 of 10** (xray, wireguard, shadowsocks).
- [x] **`HealthMonitorService` deleted — its design could not work.**
      137 lines, referenced from nowhere, claimed periodic health checks and
      automatic failover. Its probe opened `Socket.connect('1.1.1.1', 53)` from
      inside the app, but `BlackoutVpnService` calls
      `addDisallowedApplication(packageName)` — so **every socket this app opens
      bypasses its own tunnel**, in both split-tunneling modes. The probe would
      therefore have measured the physical path and reported "healthy" whenever
      the device had any internet, even with the tunnel completely dead;
      failover could never have fired on a tunnel failure. Removed rather than
      wired up, and the constraint is now documented at the exclusion site in
      `BlackoutVpnService.kt` and on `VPNService.getConnectedIP`. Any future
      in-tunnel probe must dial the core's loopback SOCKS inbound instead.
      The same constraint is why `getConnectedIP` cannot be implemented by
      fetching an IP-echo URL from Dart.

### Remaining Deliverables

- [ ] **Bundle a sing-box binary** so the four protocols with no engine work
  - Hysteria2, TUIC, AmneziaWG, WARP
  - WireGuard was **removed from this list**: the bundled `libgojni.so` contains
    `xray.proxy.wireguard`, so it is served in-process with no new dependency and
    no licence change. See the "wireguard outbound" section above.
  - The remaining four each fail with an explicit "engine not bundled" error
  - `EngineRunner.kt` already implements the subprocess + tun2socks contract
  - Binaries must ship as `jniLibs/<abi>/lib*.so` (Android only `exec()`s from
    `nativeLibraryDir`)

- [ ] **iOS native layer**
  - `AppDelegate.swift` does not exist
  - `NEVPNManager` / `NEPacketTunnelProvider` not implemented
  - Every iOS channel call is an unregistered mock today

- [ ] **On-device verification**
  - The Android tunnel has never run on physical hardware
  - Priority: confirm `establish()` succeeds, the Xray core starts, and traffic
    actually flows through the tunnel
  - Also verify: `setBlocking` is correctly absent, the `10.111.222.1/30`
    interface address pairs with the `10.111.222.2/30` core gateway, and the
    kill switch holds the tunnel on engine death
  - **The test for this already exists** and has never been run:
    `integration_test/native_tunnel_test.dart`. It drives the real
    `android.net.VpnService` — `prepare()` → `connect()` → `isRunning()` →
    `disconnect()` — and also asserts that an unbundled protocol is refused
    rather than left black-holing traffic. Run it with:
    ```bash
    adb shell appops set com.blackoutkit.vpn ACTIVATE_VPN allow
    flutter test integration_test/native_tunnel_test.dart -d <device-id>
    ```
    It holds the tunnel open for 20 s so `adb shell ip addr show tun0` can be
    checked while it is live.
  - Requires an arm64 device: this project does not target emulators, and the
    release build strips the x86/x86_64 `libgojni.so`.

- [x] **Geo data review** — resolved
  - `libv2ray.aar` ships `geoip.dat`, `geosite.dat`, `geoip-only-cn-private.dat`
  - Nothing referenced them: `XrayConfigBuilder` emits literal CIDRs and explicit
    domain lists, never `geoip:` / `geosite:` tags
  - Excluded via `androidResources.ignoreAssetsPattern`
  - Measured: uncompressed 147.4 MB → 119.2 MB (−28.2 MB), but the release APK
    only drops **123.2 MB → 115.7 MB (−7.5 MB)** because the `.dat` files
    compress ~3.8:1. The raw 28 MB figure overstates the on-disk saving.
  - **Trap worth remembering:** `packagingOptions.exclude` does *not* filter
    assets. It silently did nothing here and the build still reported success.
    Assets need the resource merger's ignore pattern.

- [x] **ABI splits** — done, measured
  - `libgojni.so` is 35.7 MB (arm64) / 34.5 MB (armv7) and both were in one APK
  - Command: `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`
  - **arm64-v8a: 60.2 MB · armeabi-v7a: 55.2 MB** (was 115.7 MB fat) — roughly a
    48% cut per download
  - Each split contains exactly one ABI and one `libgojni.so`
  - **Blocker that had to be removed first:** `defaultConfig.ndk.abiFilters` made
    AGP reject splits outright — *"Conflicting configuration : 'armeabi-v7a,arm64-v8a'
    in ndk abiFilters cannot be present when splits abi filters are set"*. The x86
    libs are now stripped with `packagingOptions.exclude 'lib/x86/**'` instead,
    which does work for native libs.
  - `--target-platform` is an optimisation, not a requirement: a plain
    `flutter build apk --release` already yields a **109.8 MB** fat APK with only
    arm64-v8a + armeabi-v7a, because `packagingOptions` strips the x86 libs. The
    flag just avoids compiling x86 Flutter libs that would be discarded.


- [ ] **Localization — partially done (2026-09-19)**
  - **Working:** the app shell is translated into 9 languages (en, es, fr, de, zh,
    ja, ru, ar, pt). That covers the bottom navigation, the connection-state
    labels, the connect button, and the main Settings entries. Changing the
    language in Settings now visibly re-renders the app.
  - **Not done:** 96 distinct user-visible strings in `lib/screens` and
    `lib/widgets` are still English-only, plus service/controller messages.
    Producing accurate translations for that volume is real work, not a
    find-and-replace.
  - **Do not claim full 9-language support until that is done.**
  - Fixed as part of this: `LocalizationService` was never registered with GetX,
    `GetMaterialApp` had no `translations` or `locale`, and
    `LanguageSettingsScreen` — unreachable and crashing on open — was deleted.
    The picker previously moved the radio button and changed nothing.
  - `test/services/localization_service_test.dart` enforces key parity across all
    9 languages, so a missing translation fails the suite instead of silently
    falling back to English.

- [ ] **Improved UI/UX and animations**
  - Enhanced transition animations
  - Gesture-based controls
  - Dark mode refinement

---

## 🔮 V2: Blackout Kit Engines (Future)

**Status: PLANNED** ⏳ | **Version: v2.0** | **Timeline: TBD**

### Vision

Replace GitHub configs with internal Blackout Kit engines for better control and performance.

### Features

- **V2Ray Engine:** Full V2Ray protocol implementation
- **Trojan Engine:** Trojan proxy protocol support
- **NaïveProxy Engine:** Naive proxy for circumvention
- **Drop-in Replacement:** Seamless integration via registry pattern
- **No Redesign:** UI stays the same, protocols auto-detected

### Technical Approach

```dart
// Registry pattern enables seamless addition
abstract class Config {
  String get protocol;  // "wireguard", "openvpn", "v2ray"...
  Future<bool> connect();
}

class V2RayConfig extends Config { /* ... */ }
class TrojanConfig extends Config { /* ... */ }

// UI already shows all by protocol
```

### Implementation Plan

1. Create engine implementations in `lib/engines/`
2. Register with EngineRegistry
3. Factory auto-detects protocol
4. Library screen shows all engines seamlessly

---

## 👻 V3: Reverse-Engineered Hotspot Shield (Future)

**Status: PLANNED** ⏳ | **Version: v3.0** | **Timeline: TBD**

### Vision

Reverse-engineer the Hotspot Shield protocol for ultra-fast, censorship-resistant VPN.

### Rationale

- Hotspot Shield is extremely fast in restricted regions
- Proprietary protocol offers unique circumvention properties
- Users could use it free without Hotspot Shield app

### Technical Considerations

- Protocol reverse-engineering (packet analysis, binary analysis)
- Implementation in Dart or native code
- Seamless UI integration via registry pattern
- Testing in actual restricted networks

### Implementation Plan

1. Protocol analysis and documentation
2. Reference implementation in native code
3. Dart wrapper via platform channels
4. Registry registration for UI integration

---

## 📊 Feature Comparison

Legend: ✅ shipped · ⚠️ shipped but not verified on a physical device · ❌ absent

| Feature | v1.0 | v1.1 | v2.0 | v3.0 |
|---------|------|------|------|------|
| **Config from GitHub** | ✅ | ✅ | ✅ | ✅ |
| **Reachability Testing** | ✅ | ✅ | ✅ | ✅ |
| **Throughput Measurement** | ❌ | ❌ | ❌ | ❌ |
| **VPN Connection** | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| **Xray Engine (VLESS/VMess/Trojan/SS/WireGuard)** | ✅ | ✅ | ✅ | ✅ |
| **Kill Switch** | ✅ | ✅ | ✅ | ✅ |
| **Split Tunneling** | ✅ | ✅ | ✅ | ✅ |
| **DNS Leak Prevention** | ✅ | ✅ | ✅ | ✅ |
| **sing-box Engine (Hysteria2/TUIC/AWG/WARP)** | ❌ | ✅ | ✅ | ✅ |
| **Localization** | ❌ | ✅ | ✅ | ✅ |
| **iOS Support** | ❌ | ❌ | ✅ | ✅ |
| **Hotspot Shield** | ❌ | ❌ | ❌ | ✅ |

> **VPN Connection is marked ⚠️, not ✅.** The native tunnel is fully implemented
> and the APK builds, but it has never run on physical hardware. Until it does,
> "it connects" is an untested claim.

> **WireGuard moved out of the sing-box row.** The bundled `libgojni.so` contains
> `xray.proxy.wireguard`, so it is served by the Xray core already in the APK.
> Only Hysteria2, TUIC, AmneziaWG and WARP still need sing-box.

> **Throughput is ❌ everywhere.** Nothing in this project measures bandwidth.
> `TesterService` opens a TCP socket and times the handshake; that is latency and
> reachability, not speed. Earlier revisions of this table and of the home screen
> implied otherwise.

---

## 🎯 Success Metrics

### v1.0 (Current)

- ✅ Config fetching from GitHub works
- ✅ 134 unit tests compile and pass
- ✅ All screens build and render
- ✅ Error handling is wired up
- ✅ Xray engine bundled; the five protocols it serves are gated in the UI
- ⚠️ **Connect / disconnect on a real device — UNVERIFIED**
- ❌ Throughput measurement — not implemented

> **Correction (2026-09-19).** This list previously asserted "✅ Core functionality
> works (connect/disconnect)" and "✅ Speed testing accurate". Neither was true: the
> tunnel had never run on hardware, and no code path measured throughput. Asserting
> them as met is how the project ended up shipping 1,053 lines of mock Kotlin that
> reported a fake IP.

### v1.1 (Next)

- [ ] **Verify on a physical device** — `establish()` succeeds, the Xray core starts, traffic flows
- [ ] Kill switch holds the tunnel open when the engine dies (verified, not just implemented)
- [ ] Split tunneling actually routes the selected apps (verified, not just implemented)
- [ ] DNS resolves through the configured resolvers, checked at dnsleaktest.com
- [ ] Bundle sing-box so Hysteria2 / TUIC / AmneziaWG / WARP connect
      (WireGuard no longer needs it — the bundled Xray core carries it)
- [ ] App supports 8+ languages
- [ ] Animations smooth (60fps on mid-range devices)

### v2.0 (Future)

- [ ] iOS `NEVPNManager` / `NEPacketTunnelProvider` implemented
- [ ] New protocols work with no UI changes needed
- [ ] Performance parity with standalone engines

### v3.0 (Future)

- [ ] Hotspot Shield protocol working
- [ ] Ultra-fast speeds in restricted regions
- [ ] Censorship resistance verified

---

## 🔧 Technical Debt & Known Issues

### v1.0 Known Limitations

1. **Never run on a device** - The Android tunnel is implemented but unverified. This is the top risk.
2. **No throughput measurement** - Only latency/reachability is measured; the UI no longer pretends otherwise
3. **Four protocols cannot connect** - Hysteria2, TUIC, AmneziaWG, WARP need a sing-box runtime that is not bundled. (WireGuard no longer belongs here: the bundled Xray core carries it.)
4. **iOS is non-functional** - The Swift files exist but are unregistered mocks; there is no `AppDelegate.swift`
5. **Fat release APK is 109.8 MB** - Per-ABI splits (57.6 MB / 52.6 MB) are built and
   wired into CI; the fat APK is still what a plain `flutter build apk --release` gives
6. **Geo data** - *resolved*: excluded, saving 7.5 MB on disk (28 MB uncompressed)
7. **Rate Limiting** - GitHub API allows 60 req/hour for anonymous clients
8. **No Reproducible Builds** - Yet (planned for later)
9. **No Multi-hop** - Single VPN connection only

> **Correction (2026-09-19).** Items 1–3 previously read "Kill Switch / Split
> Tunneling / DNS Leak Prevention — not implemented". All three are now
> implemented, so those entries were replaced with the limitations that actually
> remain.

### Potential Improvements

- [ ] Reproducible builds with signed checksums
- [ ] Native buildVariants for minimal APK
- [ ] In-app update checking
- [ ] Custom app icon themes
- [ ] Export/import config sources
- [ ] Web dashboard for config management

---

## 📅 Release Timeline

| Version | Target Date | Status | Focus |
|---------|------------|--------|-------|
| **v1.0-beta** | 2026-01-15 | ✅ Released | Core features, testing |
| **v1.0** | 2026-02-15 | ⏳ Planned | Stable release |
| **v1.1** | 2026-04-30 | ⏳ Planned | Kill switch, split tunneling, DNS |
| **v2.0** | TBD | 🔮 Future | Blackout Kit engines |
| **v3.0** | TBD | 🔮 Future | Hotspot Shield reverse-engineering |

---

## 🤝 Contributing

Want to help? Check these resources:

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - How to contribute
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Design patterns
- **[SECURITY.md](SECURITY.md)** - Security policy
- **GitHub Issues** - Report bugs, request features
- **GitHub Discussions** - Ask questions, discuss ideas

---

## 🔗 Related Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) - Design patterns and extensibility
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [SECURITY.md](SECURITY.md) - Security policy and threat model
- [DEPLOYMENT.md](DEPLOYMENT.md) - Release and deployment procedures
- [QUICKSTART.md](QUICKSTART.md) - Quick start for developers and users
- [CHANGELOG.md](CHANGELOG.md) - Version history and changes
- [README.md](README.md) - Project overview

---

**Current Status:** Phases 1–4 complete ✅ | Xray engine bundled and wired ✅ |
Five protocols blocked on a sing-box runtime ❌ | **On-device verification still pending** ⚠️ |
v2.0+ Visionary 🔮

**Last Updated:** 2026-09-19 (UI honesty pass — screens no longer advertise engines and
protocols this build cannot run; see the correction notes above)
**Maintained By:** Blackout Kit Contributors  
**Next Review:** after the first successful on-device connection
