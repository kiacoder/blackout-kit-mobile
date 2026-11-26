# Security Policy

## Reporting Security Issues

**Do NOT open public GitHub issues for security vulnerabilities.** Please report security issues responsibly:

### Report To
- **Email**: security@blackout-kit.dev
- **GitHub Private Security Advisory**: [Report vulnerability](https://github.com/kiacoder/blackout-kit-mobile/security/advisories/new)

### What to Include
1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Your name/handle (for credit if desired)

### Timeline
- **Initial Response**: Within 48 hours
- **Status Updates**: Every 7 days
- **Public Disclosure**: After fix is released and tested (typically 90 days max)

## Security Principles

This app is built on the following security principles:

### 1. Config-Based, Not Code-Based
- VPN configs come from GitHub repositories, not hardcoded
- Users choose which repos to trust
- Transparent source control (all configs visible)

### 2. Network and privacy boundaries

No developer-operated account or application telemetry is required. Config
fetches, probes, tunnel traffic, update checks and optional exit-IP lookups
contact external endpoints. Those endpoints can observe the requests they
receive. Users must trust their chosen server and configuration sources.

### 3. Local storage

The v1.19.4 candidate stores configs, sources and test results in encrypted
Hive boxes using a platform-secure-storage key. Hive 2.2.3 uses AES-256-CBC;
this is encryption at rest, not authenticated encryption. Settings are
separate. The candidate locks the library rather than writing plaintext if
the key is unavailable; ambiguous migration preserves both copies. Migration
checks the record types in all existing library boxes before deleting legacy
data, and initialization rechecks the persisted key before allowing writes. Do not
clear app data or uninstall to resolve a recovery screen. Active native
engines can require app-private transient plaintext configuration files.
Process-death cleanup and device migration verification remain open.

### 4. Transparency and permissions

Application source and native component provenance are documented. Exact
reproducible APK builds and independent audit are not yet established.
Android requires network and VPN capabilities; notifications, QR-camera
access, installed-app enumeration for split tunneling, and APK installation
are feature-dependent. Consult the merged manifest for a specific build.
iOS device connectivity is unverified.

## Security Limitations

When a supported tunnel is established and verified, the client can reduce
local-network exposure and help reach otherwise blocked services. It cannot
guarantee anonymity, protect against a malicious server or compromised
device, or eliminate every DNS, IPv6 or application-level leak. Use HTTPS
and verify the tunnel before sensitive use. See [release security evidence](docs/RELEASE_SECURITY.md).

## Known Security Considerations

### GitHub API Rate Limiting
- Anonymous users: 60 requests/hour
- **Impact**: If user has 200+ custom sources, API calls may be rate-limited
- **Mitigation**: Implement 1-hour caching (done), display rate limit message

### Config Validation
- URIs are parsed for basic validity (protocol, address, port)
- No cryptographic signature verification
- **Impact**: Compromised GitHub account could inject malicious configs
- **Mitigation**: Always use trusted, verified repositories

### Speed Testing
- Tests contact each server to measure speed/latency
- **Impact**: Reveals to VPN provider that app performed tests
- **Mitigation**: Can be disabled in settings, tests are optional

### Kill switch

Android implements a fail-closed tunnel policy for supported engine failure
paths. Android always-on VPN with lockdown is a separate system control.
Physical-device failure, handover and leak acceptance remains pending.
Do not assume a UI status alone proves fail-closed traffic behavior.

## Dependencies

Security review checklist for dependencies:

| Package | Purpose | Risk | Mitigation |
|---------|---------|------|-----------|
| **GetX** | State management | Low | Popular, 30M+ downloads, MIT license |
| **Hive** | Local storage | Low | Encrypted, popular, pure Dart |
| **http** | HTTP requests | Low | Official Dart package |
| **logger** | Logging | Low | No network access, pure Dart |
| **connectivity_plus** | Check network | Low | Official, handles permissions |
| **path_provider** | File paths | Low | Official, secure temp directories |

### Dependency Updates
- Security patches: Applied immediately
- Minor/major updates: Reviewed for security implications
- Unused dependencies: Removed regularly
- Outdated dependencies: Updated quarterly

## Testing & Verification

### Before Each Release
1. Run full test suite (`flutter test`)
2. Run static analysis (`flutter analyze`)
3. Check for new vulnerabilities: `flutter pub outdated --dependency-overrides`
4. Manual testing on real device
5. Code review by at least one contributor

### User Verification
- Check file integrity: Verify published checksums and signatures where provided
- Verify signature: Android APK signed with official key
- Audit code: Review on GitHub before downloading

## Incident Response

### If a vulnerability is discovered:
1. **Immediately**: Contact security@blackout-kit.dev
2. **Within 24h**: Create private security advisory
3. **Within 48h**: Assess severity and impact
4. **Within 1 week**: Develop and test fix
5. **On release**: Update version, publish fix, disclose responsibly

### Severity Ratings
- **Critical**: Entire userbase at immediate risk → patch urgently
- **High**: Significant subset affected → patch within 1 week
- **Medium**: Limited impact → patch in next release
- **Low**: Theoretical/edge case → patch in next release

## Compliance

- ✅ Open-source license: MIT (user freedom)
- ✅ Privacy: No data collection or tracking
- ✅ No closed-source binaries
- ✅ No third-party analytics
- ✅ No advertisements
- ✅ Works offline (after initial setup)

## Security Best Practices for Users

### 1. Choose Trusted VPN Sources
- Use GitHub repositories from known, verified providers
- Avoid random/unknown sources
- Check recent commits and code review

### 2. Monitor Your Connection
- Check reported IP address (use https://whatismyipaddress.com)
- Verify VPN is connected before accessing sensitive services
- Test speed periodically (poor speed = potential issues)

### 3. Keep App Updated
- Enable automatic updates
- Check for new app versions monthly
- Review release notes for security fixes

### 4. Use Secure DNS
- Change system DNS to secure provider (Cloudflare, Quad9, Mullvad)
- Disable IPv6 if you don't need it
- Test for DNS leaks: https://www.dnsleaktest.com

### 5. Enable Kill Switch (When Available)
- Prevent traffic leaks if VPN disconnects
- Disable auto-disconnect in critical sessions
- Test kill switch regularly

## Further Reading

- [VPN Threat Model](https://en.wikipedia.org/wiki/Virtual_private_network#Threat_model)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Dart Security](https://dart.dev/guides/security)
- [Flutter Security](https://flutter.dev/docs/security)

---

**Last Updated**: 2026-11-26

**Maintained By**: Blackout Kit Security Team  
**Contact**: security@blackout-kit.dev

## Multi-engine expansion safety (2026-11-16)

Batch exports and QR/clipboard data are plaintext credentials. The new application
batch export requests explicit clipboard consent; clipboard history cannot reliably
be erased by the app. The offline factory creates a new 0700 directory and 0600 files
on POSIX, refuses existing destinations and never prints profile contents. Keep exports
outside Git on encrypted storage. `private-exports/` is ignored for this reason.

Factory YAML uses a safe loader and rejects aliases/duplicate keys; JSON rejects duplicate
properties. It never fetches remote providers, runs OpenVPN scripts, reads referenced
keys, or connects to endpoints. These are structural checks only: engine execution may
still be unsafe for untrusted full profiles. Require trusted provenance and native checks.
No server credentials were requested in chat or invented. No server access occurred.
Native library licensing/provenance and existing raw engine log tails remain release
review items; see docs/EXPANSION_AUDIT.md. Root MIT does not relicense dependencies.

Milestone 2: native checker output is redirected to /dev/null, not captured or echoed.
EngineRunner no longer exposes raw engine log tails in user errors. Existing native
log files and other engine wrappers still require a separate complete logging review.
Mihomo is opt-in and binary-gated; its profile normalizer removes exposed controller
bindings, forces loopback-only proxy access, rejects extra listeners/scripts/fake-IP,
and maps HTTPS providers to identity-derived private cache paths. Native config checks
may initialize engine resources; importing a profile alone performs no such fetch.

### Native-build continuation
EngineRunner and the sing-box probe now discard raw native process output rather
than persisting it or returning log tails. The probe uses the bounded shared checker.
Historical log files are not automatically deleted. This does not silence all native
library/logcat output: AWG/WG JNI and existing in-process wrappers remain review gates.
Kernel test fixtures use isolated namespaces, ephemeral keys and private temporary
configs; they must not be run on production hosts. See docs/NATIVE_BUILD_PROGRESS.md.
