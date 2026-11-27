# OpenVPN and Mihomo acceptance ledger

2026-11-27, Project Blackout (development PR #29). Neither engine is approved for a production release.

## Mihomo

- Reviewed upstream VPN source: [v1.19.34, 0455d0d28c4526937380505153e65a843d8612e8](https://github.com/MetaCubeX/mihomo/tree/0455d0d28c4526937380505153e65a843d8612e8).
- Official Android ARM64 and ARMv7 compressed archives matched published SHA-256, but target API 34. Do not package them for API 24.
- Rebuilt clean pinned source on Windows using Go 1.26.11, Android NDK 28.2.13676358, CGO, PIE, with_gvisor, trimpath, and the API 24 Clang targets. Module verification succeeded; both ELF metadata checks passed.
- ARM64 SHA-256: a4d1ca8c1ec5a5ba56a181eb4d96a8dbe9da9c29f1a2bbf847124850cde3414c
- ARMv7 SHA-256: edd068a1e6b82cf252cc466ecec4899c7ad1941e4c3f2633d86355527f803d9c
- Stage using tool/stage_mihomo.py --build PATH --source PATH. It checks clean source identity, build metadata, both ABIs, API level and checksums. Staged binaries and GPL license remain local, ignored by Git.
- Linux upstream binary SHA-256: 0a68807c7c93963bb66d07717fe0f3ac3945b422b525f8a1e19438d278d7ae11. Initial run: 6 passed, 4 failed, 1 error. The readiness check was only waiting for a SOCKS handshake. A diagnostic delay passed 11/11; after changing the harness to require independent TCP and DNS readiness, 11/11 passed again. This is host loopback coverage, not Android VPN traffic.
- Private debug build: opt-in enableMihomo=true, isolated application ID suffix .mihomotest; production gate remains false. No unreviewed binary is committed.
- Private debug APK verified using explicit Gradle project arguments: package com.blackoutkit.vpn.mihomotest, both packaged SHA-256 values equal the staged artifacts. APK SHA-256 dc69ea50fbb3d5cc41fa71cae5c2b283a49ccff8e7e52c6b64776d069a849bf4. Earlier Flutter/environment-variable build silently produced the ordinary package without Mihomo; reject that output. Use tool/build_mihomo_debug_windows.ps1 for explicit build plus verification.
- Open: dependency and toolchain audit, license/corresponding-source distribution obligations, Android launch, protected socket and DNS/IPv6 traffic, routing rules/groups/providers, network switching, disconnect/cancellation, fail-closed behavior, resource use.

## OpenVPN

- Import metadata now preserves the raw profile and handles quoted endpoints, inline certificate/key blocks, connection blocks, IPv6 and invalid ports. It never reports a connection from metadata alone.
- Native candidate: [OpenVPN 3 Core 3.11.8, 4f3bdef73245d4ee9e8216c5d65baccc9568f6ef](https://github.com/OpenVPN/openvpn3/tree/4f3bdef73245d4ee9e8216c5d65baccc9568f6ef). Upstream offers MPL-2.0 or AGPL-3.0 at this revision. This is selection, not final license approval. Older 3.9 is AGPL-only.
- Use OpenVPNClient evaluation and credential interfaces, explicit socket protection, and server-pushed TUN builder callbacks. No imported script/plugin execution or arbitrary filesystem references. Preserve existing engine session ownership and teardown.
- Added a conservative, host-tested candidate runtime admission policy: self-contained profile, TUN only, no script/plugin/file references, no unknown directives, and peer verification required. This is not a complete OpenVPN grammar or native validation, and is not wired to a runnable engine yet.
- Pinned OpenVPN 3.11.8 Linux host profile probe compiled with GCC, OpenSSL and ASIO in an isolated Docker image. Six synthetic native cases passed (interactive and certificate-only authentication metadata, empty profile, missing remote, existing external file reference, oversized input). Probe SHA-256 63f5c3c98c800096459f26b8984e00606ef1409920737be062cf744355b18bec. Build and test scripts: tool/test_openvpn3_host_windows.ps1. Native evaluation is not a TLS handshake or Android VPN acceptance; dependencies and image are not release-audited.
- Open: Android native dependency build and audit, JNI bridge, credential lifecycle, Android VpnService/TUN integration, remote selection, TCP/UDP, server-pushed routes and DNS, IPv6, reconnection, cancellation, fail-closed behavior and device verification.

## Tests and release gate

99/99 targeted Dart regressions and the full 642/642 Flutter test suite passed; flutter analyze reported no issues. 8/8 Python artifact and staging tests passed. ADB showed no attached Android device, so neither engine can be marked Android-verified. Keep the published release and existing working engines unchanged. Do not merge or ship based only on import, build, or host-test evidence.

Follow-up: 645/645 full Flutter tests passed before final admission refinement; 9/9 focused Flutter tests, 13/13 artifact/packaging tests, and analyzer clean after refinement. Android device remains unavailable.
