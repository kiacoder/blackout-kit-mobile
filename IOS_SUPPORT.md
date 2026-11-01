# iOS Support — what works today, and the three paths to a working install

Updated: 2026-11-01

## What already works (no account needed)

The **build** is fully solved in CI:

- `.github/workflows/ios.yml` — the compile gate. On GitHub's free
  `macos-15` runners it: installs Go, builds sing-box's
  `Libbox.xcframework` (pinned gomobile fork via `tool/build_libbox.sh`),
  runs `flutter build ios --no-codesign`, and verifies the
  `BlackoutTunnel.appex` is built **and** embedded in `Runner.app`.
  Green on every push that touches `ios/` or `lib/`.
- Signing plumbing is ready: both targets carry entitlements
  (`packet-tunnel-provider` + App Group `group.com.blackoutkit.vpn`),
  and `.github/workflows/ios-release.yml` produces a **signed IPA** the
  moment signing secrets are added (see below).

## The one hard wall

A **free** Apple ID cannot grant the
`com.apple.developer.networking.networkextension` (packet-tunnel-provider)
entitlement in a provisioning profile. AltStore/Sideloadly re-signing with a
personal team strips it, and iOS will not launch a PacketTunnelProvider
without it. The app installs and runs; the tunnel does not start. This is an
Apple policy, not a bug in the project.

## The three real paths

| Path | Cost | Result |
|------|------|--------|
| **A. Paid Apple Developer account** | $99/yr | Everything unlocks: signed IPA from CI (fill the `IOS_*` secrets in `ios-release.yml`, run it, download the IPA), installs on any device via ad-hoc profiles, or TestFlight/App Store. This is the only path for arbitrary iPhones on any iOS version. |
| **B. TrollStore** | Free, no account | TrollStore 2 perma-signs any IPA on **iOS 15.5 – 16.6.1 and 17.0** via the CoreTrust bypass, and installed apps keep their declared entitlements. Download the unsigned IPA from the existing `ios.yml`/`build.yml` artifacts, open it in TrollStore, and test whether the tunnel launches. Community reports show NetworkExtension tunnels working under TrollStore — but this is unverified for Blackout Kit and needs a real device test. |
| **C. Free Apple ID sideloading** | Free | App installs (7-day resign via AltStore/Sideloadly), **tunnel will not start** (entitlement stripped). Only useful for UI-only testing. |

Practical note for Iranian users: Apple Developer Program enrollment needs a
payment method outside sanctioned channels — the common route is a trusted
relative/reseller abroad enrolling (or gifting an account). With just the
Team ID + certificate + profiles shared back, this repo's CI does the rest.

## How to use Path A (paid account) — exact steps

1. Enroll at developer.apple.com; note your **Team ID**.
2. Create two App IDs (enable Network Extension capability on both):
   - `com.blackoutkit.vpn` (app)
   - `com.blackoutkit.vpn.tunnel` (extension, "Is App Extension")
3. Create two provisioning profiles matching your export method
   (`ad-hoc` → Ad Hoc profiles listing your device UDIDs; TestFlight →
   App Store profiles). Download both `.mobileprovision` files.
4. Create an Apple Distribution certificate; export cert+key as `.p12`.
5. Base64-encode all three files and add repo secrets:
   - `IOS_P12_BASE64`, `IOS_P12_PASSWORD`, `IOS_TEAM_ID`,
     `IOS_PROFILE_APP_B64`, `IOS_PROFILE_TUNNEL_B64`
   - optional variable `IOS_SIGNING_METHOD` (`ad-hoc` default,
     `app-store-connect` for TestFlight)
6. Run the **Release iOS (signed IPA)** workflow → download the
   `blackout-kit-ios-signed` artifact → install via Finder / AltStore /
   TrollStore / TestFlight (depending on method).

## Native side status

- `PacketTunnelProvider.swift` + `VpnPlatformPlugin.swift` are written and
  typechecked in CI; `libboxMode` config building in `vpn_service.dart`
  mirrors the Android sing-box grammar (same engine, same config shape).
- App Group `group.com.blackoutkit.vpn` declared on BOTH targets (Runner +
  BlackoutTunnel) — the provider falls back to tmp storage when the group
  container is unavailable (free-account builds).
- No Dart changes are needed when signing arrives; the Swift/Dart channel
  contract is already consistent.
