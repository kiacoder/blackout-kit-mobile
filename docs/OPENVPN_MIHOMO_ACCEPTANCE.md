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

## Native bridge checkpoint (2026-11-27)

- Added a candidate C++ OpenVPN ClientAPI adapter, JNI handle ownership, bounded input and redacted callback diagnostics, and Android VpnService.Builder callbacks with service-side descriptor retention. The bridge is not registered with the normal VPN service.
- Six C++ callback-contract tests passed on Linux. Host JNI smoke passed using a real Linux shared library and JVM (single owner, stale handles, cancel-before-run, bounded input and failed callback lookup). Android Kotlin compilation passed.
- Cross-built both Android API 24 ABIs from OpenVPN 3.11.8 and candidate dependencies Mbed TLS 3.6.8 (82e69999f91126589a28b70dd75b69fbcabe2711, framework ced31491c5ec907a6be533512f19dc1779230ac1), ASIO 1.39.0 (190a8d8daf1cc62909b4e0c72ff491ba264ca98e), xxHash 0.8.4 (c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0). NDK 28.2.13676358, CMake 3.22.1. This candidate uses Mbed TLS rather than the host OpenSSL probe; dependencies and distribution notices are not release-audited.
- ARM64 SHA-256: 7a13ab737fd0e8b99067edef460a18ba612e4a975b24cfaa76f1fdc869248b6c.
- ARMv7 SHA-256: 29e1385027893db96cf10d97af593cb4310f7a1a4d07103a78e9f6bd027ec227.
- Both candidates pass ELF ABI/API and all four JNI export checks. Use tool/build_openvpn_android_windows.ps1 with clean pinned sources and tool/stage_openvpn_candidate.py to stage and verify both ABIs. Opt-in Gradle property enableOpenVpnCandidate creates a separate .openvpntest debug package. It is intentionally incompatible with other experimental build flags. Normal release packaging remains unchanged.
- This initial callback contract is limited to full-tunnel IPv4, optionally full-tunnel IPv6. No route exclusions, DNS fallback, unsupported split DNS/DoH/DoT, external PKI, encrypted private keys or interactive challenge handling. It is not a complete OpenVPN implementation. Real server handshake, Android load/traffic, cancellation races, lifecycle integration, profile admission at the actual service boundary and credential UI are outstanding. Do not advertise production support.
- 14/14 Python candidate/artifact tests passed. No device was attached for instrumentation.

Private debug APK package identity and exact binary hashes verified: 938dd9e2a07fe7e18e975a9a0a6dadfa9a87900c10137fc186751b1c7b5129b6. Android instrumentation APK built successfully after resolving an existing uncached jsr305 test-classpath artifact; SHA-256 24df24a874692ffd6440039bebc02917975beeb5d95ad462a2364e50d798fdb8. Neither APK has been installed or run on Android.

Final Kotlin quality audit: zero findings after correcting six issues without suppression. Final app and instrumentation APKs rebuilt and native bytes verified.

## Private service integration checkpoint

- OpenVPN now has a Flutter channel -> non-exported Android VPN service -> serialized session owner -> dedicated native worker path in the opt-in .openvpntest package. Release flag is false. The packaged capability is advertised only when both the flag and library are present.
- The first service-side admission subset is certificate-only, inline CA/certificate/key, server certificate verification, full tunnel, simple ASCII profile syntax. No auth-user-pass, external files, unknown directives, quoted or connection-block syntax. The app's DNS override is not applied: only routed server-pushed DNS is accepted by the candidate. No split tunneling.
- Worker reports connected only on the native event and current session ticket. Startup waits at most 30 seconds for readiness (cancellation and cleanup may add time). Cleanup cancels and joins the worker before release, retaining ownership on timeout. Monitor stops a failed session; holding the retained TUN on requested kill-switch failure is implemented but not device-verified. Automatic reconnection and system lockdown behavior remain unverified.
- Fixed OpenVPN address-family callback incompatibility: core calls it for full-tunnel profiles; never grant Android allowFamily bypass. Both ABIs rebuilt and passed metadata and JNI exports.
- Revised native SHA-256: ARM64 8c552f8f64a46819160ed009c466dc4599336002d699078696413c1d3fe68a3b; ARMv7 0d482078d4f8cf9d4055abc46a44f626b429cd8e1a916c1f19cc6d753bcbf996.
- Debug APK SHA-256 832cce18fea8222a6b153fdfb7bbd73e23671cbddfc4ae346636221e3a9efd98. Both packaged binary hashes verified; instrumentation APK SHA-256 a889c356e4b5fcae2b78cb7f2c82f0c5eaca28ad4adf30b41d1f849988d7c681. No device attached; not installed or executed.
- Full Flutter 646/646 and Android JVM 98/98 passed; six Linux callback contract tests passed; Kotlin quality and Flutter analysis clean. Updated structural regression check for both TUN owners. Corrected pre-existing local JVM mock SDK zero handling for legacy symlink checks, preserving actual API 24/25 behavior. No dependency version changes.
- Still required: live controlled OpenVPN server handshake and TCP/UDP traffic; Android device load, forwarding and DNS/IPv6 leak acceptance; authentication UI; broader profile compatibility; reconnect/failure handling; security/license audit. Mihomo remains pending device acceptance. Do not mark either engine production supported.

## Interactive authentication checkpoint

- Direct connections now prompt for username/password in English, Persian or Chinese when an imported profile contains bare auth-user-pass. The service accepts an inline CA with an inline client certificate/key pair, or with interactive credentials, or both. Incomplete cert/key pairs and file-based auth-user-pass remain rejected.
- The Flutter method channel sends bounded byte arrays. Android hands off the arrays through a process-local single-use token, not credential-bearing Intent extras. Pending credentials are discarded on resolution or plugin detach; mutable buffers are cleared on completion. UI strings, method-channel serialization and upstream core copies cannot be guaranteed wiped. No plaintext or persistent credential storage was added. Saved credentials, encrypted private key passwords and OTP/challenge flows remain pending.
- Native preparation now evaluates profiles and provides credentials before connect. For explicitly admitted username/password-only profiles the candidate disables client certificate presentation; this does not disable server verification. Eight Linux callback/preparation cases passed, including missing and provided credentials. No real server authentication was exercised.
- Full Flutter suite 648/648, Android JVM 101/101, static analysis/ktlint/Detekt clean. Both native libraries rebuilt from the same pinned dependencies and verified in the isolated debug APK.
- ARM64 SHA-256 4dd324981e5a368d928f1aa02ca286a14acc4688292aee3839931e8441fb3f01; ARMv7 f2054b19602de42f4e96562698c5d729d63432e9e764b6272c73825e3a28002a. Debug APK SHA-256 6dfed72b0904f34c5bf48165b9e467a5104e05ea95cef26af53975aefea077cf; instrumentation APK a889c356e4b5fcae2b78cb7f2c82f0c5eaca28ad4adf30b41d1f849988d7c681.
- No attached Android device. Full authentication handshake, traffic, reconnection, leak and release gates remain open. No dependency version change or production capability promotion.

## Saved login and encrypted key checkpoint

- Optional remembered login is attached to an existing encrypted profile record, not the URI or Config object. The default for new credentials is off. Existing saved values are prefilled; unchecking and submitting removes the saved login. The explicit save/remove choice takes effect before the connection attempt (even if authentication subsequently fails). Profile deletion and clear-all remove the record; this is logical deletion, not a guarantee of physical erasure. No login is persisted for an unsaved profile. Private-key passwords are always session-only.
- Encrypted PEM detection and separate private-key password input now feed Config.privateKeyPassword through a versioned nativeRunV3 JNI ABI, with a fixed three-field authentication array. Missing required key password is rejected during native preparation. The ABI verifier requires RunV3 so stale artifacts cannot be staged as current. Two generated encrypted PEM preparation cases pass, in addition to eight callback/auth preparation cases; actual key decryption in the Android TLS runtime and live authentication are still unverified.
- 651/651 Flutter tests, 102/102 Android JVM tests, 10/10 Linux callback/preparation cases, 14/14 Python artifact tests, host JNI smoke, Flutter analyzer, ktlint and Detekt all passed locally. Encrypted vault test checks restart, no literal password on disk, no key password saved, URI unchanged and deletion/re-import behavior. Both ABIs rebuilt and exact APK bytes verified.
- ARM64 SHA-256 20ab855c51560060eb4328f20232da6b5635853227205c11b66077a7d457648c; ARMv7 813cd7715814d1abdb53e6ae32820a2a6061741fa5a7ef58e7e7aa49f164dce5. Debug APK SHA-256 d9365815f5cefd3db1eccd7e6377a69025480c0a173e9869eb50f44b1f6101d8; instrumentation APK 95133d6714dc383b5157ecabeed7be3bfad71ead8fc8bd2d4fd3d7db763e3e78.
- Prior commit's GitHub narrow Android source compile failed because the source list and compile-only BuildConfig lacked OpenVPN. Updated the script to include the new files/flag and pinned AndroidX annotation API. Fresh remote CI still required. No dependency version changes to the application.
- No Android device attached. No production release or promotion. Live TLS authentication, forwarding, DNS/IPv6 leak and recovery tests remain mandatory.
