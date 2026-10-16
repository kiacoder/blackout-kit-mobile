# Changelog

All notable changes to Blackout Kit Mobile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta.13] - 2026-10-11

### Fixed
- **XUDP base key, second attempt: the gomobile JNI bridge mangled raw
  high bytes (P0).** beta.12 passed the raw 32 digest bytes through a Java
  string in ISO-8859-1 — but the Java→Go string border re-encodes to
  UTF-8, so every byte above 0x7F became a multi-byte sequence, and the
  core received a mangled key it counted as length 0 ("BaseKey must be 32
  bytes: âQyXÛÎ=*… len 0" — captured from the device). The key was changed to
  ASCII-safe bytes, but device testing showed Xray expects the setting in
  unpadded URL-safe Base64 rather than as literal key bytes; see the unreleased
  follow-up below.

## [1.0.0-beta.12] - 2026-10-11

### Fixed
- **THE first-connect blocker (found from the first real device error!):
  the XUDP base key was the wrong length (P0).** `xudpBaseKey` SHA-256'd a
  device seed into exactly 32 bytes — then Base64-encoded them into a
  44-character string. The core reads that env var AS the key itself and
  requires precisely 32 bytes, so every connect died at core init with
  "xray.xudp.basekey: invalid value (BaseKey must be 32 bytes)". The raw
  digest bytes now pass through unchanged (ISO-8859-1, byte-exact).
  This single line was why no VLESS/VMess/Trojan/SS/WireGuard config could
  ever start the engine on device.

## [1.0.0-beta.11] - 2026-10-11

### Fixed
- **The real engine failure reason was trapped in the engine object (P1).**
  When `XrayEngine.start()` failed, its detailed `lastError` ("Xray core
  rejected the configuration: ...") never reached `BlackoutVpnService`,
  which fell back to the generic "Engine failed to start for protocol
  'vless'" — hiding exactly the message needed to debug the first on-device
  run. The engine's and runner's own errors are now surfaced verbatim to
  the UI.

### Validation
- All six protocol shapes the Dart `XrayConfigBuilder` emits (VLESS
  REALITY/TCP, VLESS WS+TLS, VLESS plain, VLESS gRPC+TLS, VMess WS, SS)
  were validated against a real Xray 26.3.27 core with `xray run -test`:
  **every configuration parses clean**, including the `tun` inbound shape.
  The first on-device engine failure is therefore NOT a config-grammar
  problem; beta.11's verbose error will name the actual cause.
- `tool/emit_xray_config.dart` added to reproduce the validation.

## [1.0.0-beta.10] - 2026-10-11

### Fixed
- **IPv6 leak closed (kill-switch style).** The tunnel used to install only
  an IPv4 address and a `0.0.0.0/0` route, so on dual-stack networks IPv6
  traffic bypassed the tunnel entirely. The tunnel now also routes `::/0`
  into the TUN *without* giving the interface an IPv6 address: v6 packets
  enter the tunnel and are dropped (nothing leaks), and apps fall back to
  IPv4 per Happy Eyeballs, which is proxied normally. This is the same
  approach used by NetGuard-class apps. Granting real IPv6 through the core
  (v6 address + v6 gateway in the tun inbound) remains future work that
  needs on-device verification.

## [1.0.0-beta.9] - 2026-10-11

Deep bug sweep across the Dart and native layers (two independent line-by-line
reviews). This release fixes the real causes of "engines start to fail" and
"the tester doesn't work".

### Fixed
- **`getEngineInfo` hardcoded `singboxAvailable: true` while no sing-box
  binary is bundled (P0).** The Dart pre-flight therefore believed
  Hysteria2 / TUIC / AmneziaWG / WARP configs were servable, ranked them like
  any other server, and the engine refused them the moment it was asked to
  dial — the reported "engines start to fail". Availability is now a real
  check for `libsingbox.so` in `nativeLibraryDir`; when absent, those
  protocols are reported unavailable and the pre-flight filters them out
  instead of failing mid-connect.
- **AmneziaWG junk-packet parameters were emitted into the WireGuard
  `reserved` field (P1).** `reserved` is the 3-byte WireGuard header field
  (a WARP thing), not AWG obfuscation — AWG servers were dialled as vanilla
  WireGuard and failed the handshake instantly. The parameters now go into
  sing-box's `amnezia` block.
- **Test results were never persisted (P1).** Every restart wiped the tester
  back to "Untested" for the whole library, dropped the rankings and the
  fastest-config banner, and forced connectFastest to probe blind. Results
  now persist to Hive and hydrate on startup.
- **`TestResult.fromJson` demoted every loaded result to `notTested` (P1).**
  `toJson` stores `"TestStatus.success"` but the parser built
  `'TestStatus.TestStatus.success'` and silently fell back to notTested. The
  parser accepts both forms now.
- **Dedup never re-attributed configs to their new source (P1).** Configs
  fetched under a retired/renamed source id kept the stale `sourceId`
  forever, so per-source counters read a permanent 0 with a full library.
  A dedup hit under a new source id now rewrites the stored attribution.
- **The native `'error'` status was silently dropped (P1).** When the engine
  died with the kill switch off, the service tore the tunnel down but Dart
  kept showing "Connected" with a ticking uptime. The status is now handled
  and carries the real failure reason from the native side.
- **`XrayEngine.controller` was not `@Volatile` and stop was unsynchronised
  (P1).** Written on the establish worker thread, cleared from the main
  thread — a stale read could skip `stopLoop()` and leave the core running
  against a closed TUN fd.
- **The TUN fd was closed twice (P1).** The Xray tun inbound takes ownership
  of the fd it is handed; handing it the raw fd meant teardown's later
  `close()` targeted a possibly-recycled descriptor. The engine now gets its
  own duplicated descriptor.
- **A half-started core leaked when `startLoop()` threw or `isRunning` was
  false (P1).** The failed controller is now stopped explicitly.
- **The 20s connect timeout left a half-built tunnel running (P2).** On
  timeout the plugin now also posts a disconnect so Dart state and tunnel
  reality stay consistent.
- **Reachability progress counted double (P2).** `onProgress` fires a
  `testing` event at probe start plus a terminal event; both consumers
  counted both, so progress bars completed at 50% real progress.
- **`ConfigService.getConfigCount()` could return -1** on a fresh box.
  Counts real keys now.
- **Speed Test screen: every WORKING server displayed "Failed" in red**
  because throughput is never measured and the row rendered
  `speedMbps == null → "Failed"`. Rows now show Working/Failed plus latency;
  "Test All" uses the same bounded concurrent sample as the home screen
  instead of walking the entire library sequentially (thousands of configs ×
  up to 12s each = days).
- **Settings repository rows now show a LIVE per-source config count**
  (counted from the config box) instead of the stored fetch-time snapshot.

### Known issue (open)
- The tunnel installs only an IPv4 address and a `0.0.0.0/0` route. On
  dual-stack networks IPv6 traffic bypasses the tunnel entirely (a leak,
  not a crash). Needs a deliberate design pass — add an IPv6 address +
  `::/0` route and v6 support in the tun inbound, or block v6 — before it
  can be fixed without hardware to verify on.

### Tests
- `test/services/test_result_persistence_test.dart` — persistence round-trip,
  status parsing, per-source live counts, dedup re-attribution.
- `test/singbox_config_test.dart` updated for the `amnezia` block contract.

## [1.0.0-beta.8] - 2026-10-11

### Fixed
- **The library could sit on "Loading repositories & configs..." for many
  minutes.** Two compounding causes, both felt hardest behind censorship:
  - `GitHubService` used a bare `Dio()` with **no timeouts**. A host that
    blackholes the connection (typical for `raw.githubusercontent.com` behind
    censorship) hung for the OS-level TCP timeout — minutes — per URL, and a
    source whose filename misses tries up to a couple of dozen URLs. Requests
    now give up at 8s (connect/send) / 20s (receive).
  - The Library screen showed a full-screen spinner whenever *any* network
    work ran, including the startup refresh and the reachability tests,
    because they all flipped the same `isLoading`. Sources now fetch
    concurrently under a refcounted `isRefreshing`, and the Library renders
    its stored list immediately with refresh progress shown as a banner.
- **Connect picked censored servers and the engine died instantly.** The
  reachability probe counted a TCP **connection refused (RST)** as "reachable"
  because a RST proves the host is alive. Behind censorship that is poisonous:
  DPI boxes answer blocked destinations with an *instant* RST, so the probe
  reported "reachable in 2 ms", `connectFastest` crowned the fastest server in
  the list — the one the censor had just refused — and the engine errored the
  moment it dialled. A refused port is now a probe failure with a
  self-explanatory error. (`ECONNREFUSED` 111/61 plus Windows 10061.)
- **"Finding fastest config..." could hang for ~5 minutes of dead silence.**
  The pre-flight re-probed 150 candidates at 3 attempts × 4s with only 6 in
  flight, and re-probed servers the library had already measured as dead. It
  now skips known-failed results, probes once at a 3s timeout with 16 in
  flight, and streams live progress ("Testing servers... 37/150") into the
  status line.

### Tests
- `test/services/tester_probe_test.dart` — a listening port measures as
  working; a refused port is a failure, not "reachable".

## [1.0.0-beta.7] - 2026-10-07

### Fixed
- **~31% of shadowsocks configs were silently dropped**: the display name after
  `#` in a share link is only cosmetic, but `ShadowsocksConfig.fromUri` ran it
  through `Uri.decodeComponent` with no guard. Subscriptions embed a literal
  `%` (or other invalid percent sequence) in the name all the time, the decode
  threw, and the exception propagated to the outer `catch`, voiding the entire
  link. Measured against the real `All_Configs_Sub.txt`: unparsed ss links fell
  from 289 to 2 once this was fixed — 287 recovered. The same latent throw
  existed in the `vless` / `trojan` / `hysteria2` / `tuic` parsers via
  `Uri.parse`. Both now go through tolerant helpers: `ConfigParser.safeFragment`
  (bad name returned raw instead of throwing) and `ConfigParser.tryParseUri`
  (retries without the fragment before giving up).
- **Shadowsocks links with a query string got the wrong port**: the parser did
  not strip `?type=tcp` (and any other transport metadata) from the server part,
  so `int.tryParse` on the port failed and every such link silently fell back to
  port 8388. The server part is now split on `?` first. This is what made the
  shadowsocks-2022 links connect to the wrong port even once they parsed.

### Added
- `ConfigParser.safeFragment` and `ConfigParser.tryParseUri` — tolerant parsing
  helpers so a malformed display name never discards a usable server.

### Tests
- Added coverage for a malformed fragment on `ss://` and `vless://`, and for
  shadowsocks-2022 parsing.

### Notes
- The remaining 45 unparsed links across all sources are genuinely malformed
  (port ranges like `21000-21199`, `@` inside the userinfo, unencoded special
  characters in passwords, and subscription metadata comments) and are correctly
  rejected by `validate()`.
- Engine-build failures remain 0 across all protocols (re-verified against the
  full ~7.8k-line subscription after this change).

## [1.0.0-beta.6] - 2026-10-07

### Fixed
- **VLESS configs failed to build ("vless engine gives an error")**: measured
  against a real 7,325-config subscription, 30 configs threw while being turned
  into an Xray outbound — 28 for a missing `sni`, 2 for a missing `pbk`. Only 2
  were genuinely unusable.
  - `sni` is now recoverable. REALITY needs *a* server name to present, and the
    Host header, failing that the address itself, is a valid substitute. The 28
    configs build now.
  - REALITY without `pbk` is rejected at import instead, so a link that cannot
    handshake never reaches the engine. Same 2 configs, but they are skipped
    rather than surfacing as an error.
  - Re-running the measurement after the fix: 7,262 built, 0 failures.
- **The library was unusably slow with a full source loaded** — three separate
  causes, all of which only appear at the ~7.6k configs these sources return:
  - `saveConfigs()` wrote to Hive one config at a time, and each `put` also
    re-read and re-wrote the growing de-duplication map. Now a single `putAll`.
  - `getFilteredConfigs()` re-sorted and re-filtered the entire list on every
    rebuild, and it was called inside `Obx`, so a rebuild could trigger more
    rebuilds. The result is now memoised on the filter/sort state and
    invalidated only when the underlying configs or test results change.
  - The list built a widget for every config. It now renders 50 and offers a
    "show 50 more" button.
- **`connectFastest` fell back to the sequential tester**: with no cached
  results it probed one config at a time — 4s timeout x 3 attempts each — over
  thousands of candidates. It now uses the concurrent tester over a bounded
  sample of 150.

### Added
- `ConfigController.showMoreConfigs()` and `visibleConfigLimit`, backing the
  windowed library list.

### Tests
- Replaced `REALITY without a server name is refused`, which asserted the old
  fatal behaviour, with three tests covering the fallback chain (address, Host,
  then `sni`).
- Added coverage for the import-time REALITY public-key check.

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

## [1.0.0-beta.19] - 2026-10-16

### Added
- **Before / Now IP + location on the home screen.** The card shows the
  address and place the user had before the tunnel (direct lookup — the app
  is a disallowed application of its own VPN, so a direct fetch always sees
  the real address) and the exit address + city/country/flag fetched
  **through** the tunnel via the new `tunnelFetch` channel method. Unresolved
  lookups hide rather than show a wrong place. Both identities are cached in
  Hive: the last known home location stays visible during a blockade, when
  no lookup can succeed.

### Notes
- Config persistence was already blockade-proof (every fetched config is
  stored additively in Hive, deduplicated by hash, and the library reads
  from storage — a dead GitHub changes nothing about what is already
  downloaded); the error state already says saved configs are not lost.
- 6 new unit tests for response parsing, flag building and cache round
  trips.

## [1.0.0-beta.18] - 2026-10-16

### Added
- **Batched full-scan: `connectFastest` now walks ALL configs, not just a
  lucky window.** With thousands of sources, one probe pass was a lottery.
  The candidate list is scanned in batches of 50: TCP-probe the batch, run
  the headless site check on its fastest survivors, then connect and
  live-verify them in rank order (up to 10 per batch). Only a fully
  exhausted batch advances to the next 50 — so with 7,000 configs the scan
  eventually tries everything, while the status line always shows which
  batch is being scanned. Known-failed results from the library are skipped
  up front. Connection may take longer when the first batches are all
  blocked; that is the scan working, and it beats a "connected" notification
  that loads nothing.

## [1.0.0-beta.17] - 2026-10-16

### Fixed
- **Self-healing connect loop: a tunnel that comes up but loads nothing no
  longer strands the user.** First hardware reports showed the tunnel
  connecting (notification on) while no traffic flowed — a config can pass
  every pre-connect probe and still black-hole real traffic once the TUN
  interface is up. `connectFastest` now walks ranked candidates (site-check-
  verified first, then TCP latency) and after each successful connect asks
  the live tunnel itself to fetch the check hosts through its own loopback
  SOCKS inbound (port 10808). A tunnel that cannot reach a single host is
  disconnected and the next candidate is tried — up to 5 attempts — with the
  status line showing each attempt. If every attempt dead-ends, the error
  says so honestly instead of pretending to be connected. With the site
  check disabled the flow is unchanged (single connect, no verification).

## [1.0.0-beta.16] - 2026-10-16

### Added
- **Site check: candidate configs are now verified against real websites, not
  just pinged.** A TCP probe proves the network path to a config's server —
  it cannot prove the config carries traffic (bad credentials, a REALITY key
  mismatch or a censor black-holing the exit all leave the handshake green).
  `connectFastest` therefore shortlists the fastest TCP-passing candidates
  and checks each one in a **headless core instance**: a SOCKS-only Xray
  config (`tunEnabled: false`) runs without VpnService, consent dialogs or
  any change to the device's routing, and each check host is fetched through
  the core's loopback SOCKS inbound. Any HTTP response counts as reachable —
  even a 403 proves the round trip through the exit — while connect failures
  and timeouts count against the config. Selection prefers verified-usable
  configs (most reachable hosts first), uses tunnel latency as the tie-break,
  and every failure mode (engine refuses, tunnel already up, stage disabled)
  degrades to the previous pure-TCP ranking.
- **Settings → Site Check.** A toggle (default on) and an editable host list
  (one host per line, sanitised on input, defaults restored if everything is
  removed). Defaults: google.com, gemini.google.com, youtube.com,
  crunchyroll.com, instagram.com, facebook.com — plus github.com and
  wikipedia.org, chosen as high-uptime global fronts where "unreachable
  through this config" means the config is broken, not the site.
- 14 new unit tests covering URL sanitisation, report scoring and the
  pickBest ranking. The suite is now 176 tests across ten files (183
  including the integration suites on CI).

## [1.0.0-beta.15] - 2026-10-16

### Fixed
- **Malformed UUIDs are now rejected at validation instead of failing inside the
  core.** VMess, VLESS and TUIC embed a UUID as the client identity, but
  `validate()` only checked that the id was non-empty. A malformed-but-non-empty
  id (common in public share-link scrapers) passed validation, was written into
  the generated engine config verbatim, and died deep inside Xray/sing-box with
  a generic init error the user could not act on. A shared `isValidUuid()`
  helper (RFC 4122 shape: 8-4-4-4-12 hex) now backs all three validators, and
  because `validate()` also gates library import, such configs are dropped at
  import time with a clear cause.

### Added
- Seven new unit tests pinning the fail-fast behaviour for vless, vmess and
  tuic (malformed ids rejected, canonical ids accepted). The suite is now
  162 tests across nine files.

### Docs
- Documentation refresh across all markdown files: test counts corrected
  (155 → 162), `PHASE4_SUMMARY.md` test-file list replaced with the files that
  actually exist, APK size figures re-measured on the beta.14 CI build
  (120.6/111.7 MB — fat-APK scale; `--split-per-abi` status flagged for
  re-verification), `DEPLOYMENT.md` CI checks updated (no iOS builds — the iOS
  job was removed), `ARCHITECTURE.md` lazy-loading note corrected, and
  Last Updated stamps refreshed.

## [1.0.0-beta.14] - 2026-10-16

### Added
- **Current IP address display (Phase 3 deliverable, previously an honest stub).**
  `VpnPlugin.getConnectedIP` now fetches the exit address of the tunnel by
  dialing `https://api.ipify.org` through the core's loopback SOCKS inbound
  (`127.0.0.1:10808`, noauth) — the approach PHASES.md prescribed at the
  exclusion-site note ("any future in-tunnel probe must dial the core's
  loopback SOCKS inbound"). A direct fetch was never an option: the app is a
  disallowed application of its own VPN, so it would report the *unprotected*
  address. The request runs on a background thread with an 8 s timeout, the
  response is validated as an address literal, and any failure returns `null`
  so the status row stays hidden exactly as before. Known trade-off: the echo
  hostname is resolved by the system resolver before the SOCKS dial — one
  hostname per connect, user-triggered, not a passive browse-time DNS leak.
- **Library screen error state.** A failed config fetch used to render the same
  "No configs found" empty state as a genuinely empty library, so the user had
  no way to see *why* the list was blank. `ConfigController.fetchFromSource`
  now records the failure on the source (`ConfigSource.error`, truncated to
  120 characters) and clears it on the next success (new `clearError` flag on
  `copyWith`, because a plain `error: null` used to coalesce back to the old
  value). The screen shows a distinct error state naming the failing sources
  and their reasons, with a Retry button. New model tests:
  `test/models/config_source_test.dart`.
- **Subprocess engine startup checks.** For sing-box-backed protocols (Hysteria2, TUIC, AmneziaWG, WARP), `EngineRunner` no longer reports success the instant both processes launch. Both children must survive a bounded startup window, and sing-box must answer a real local SOCKS5 greeting on its configured `listen_port`, before the VPN service reports connected. A daemon monitor thread then watches both children: an unexpected exit now drives the same engine-died path as the in-process Xray core — tearing the tunnel down with the real reason, or holding the interface open when the kill switch is on. A failed sing-box config write now fails the connect attempt with the actual write error instead of a downstream launch failure. These checks prove process and listener readiness only — end-to-end tunnel traffic still requires a physical-device test.
- **JVM unit tests for the subprocess lifecycle** (`android/app/src/test/.../SubprocessLifecycleTest.kt`): the local SOCKS5 readiness handshake against a loopback fake server, immediate child-exit rejection, later-exit detection, and reverse-order cleanup — no emulator or device required.

### Changed
- **Settings switches that could not control their stated behavior are now disabled with accurate explanations** (their stored values are preserved):
  - *Block Non-VPN Traffic* — system-wide lockdown is controlled by Android's Always-on VPN + "Block connections without VPN"; the in-app switch never wired to it. The tile now says so.
  - *Show Notifications* — the VPN foreground notification is required by Android while the tunnel is active and cannot be hidden by the app.
  - *Log Local Connection* — no separate local connection history is implemented.
- **Settings → About now shows the real version from package metadata** (`package_info_plus`) instead of the hardcoded `1.0.0-beta.3` string.

### Docs
- Honesty pass across README / QUICKSTART / ARCHITECTURE / PHASES: Hive storage is documented as **unencrypted at rest** (previous "encrypted" claims were not backed by any cipher in the code; enabling encryption in-place would strand existing data, so it needs a designed backup-first migration); the iOS VPN layer is marked **not implemented**; protocol support is scoped explicitly — VLESS/VMess/Trojan/Shadowsocks/WireGuard run on the in-process Xray core, while the sing-box-backed protocols are gated on bundled-runtime capability plus the new local readiness checks, which do not verify end-to-end traffic.

### Fixed
- XUDP base-key initialization now passes the 32-byte digest as unpadded
  URL-safe Base64, matching Xray's `RawURLEncoding` environment parser while
  keeping the gomobile-bound string ASCII-safe.
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
