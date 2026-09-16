# Security Policy

## Reporting Security Issues

**Do NOT open public GitHub issues for security vulnerabilities.** Please report security issues responsibly:

### Report To
- **Email**: security@blackout-kit.dev
- **GitHub Private Security Advisory**: [Report vulnerability](https://github.com/blackout-kit/blackout-kit-mobile/security/advisories/new)

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

### 2. No Backend Dependence
- ✅ App works entirely offline after initial config fetch
- ✅ No phone-home telemetry
- ✅ No account system or login
- ✅ No data sync to servers

### 3. Encrypted Local Storage
- Configs stored in Hive (encrypted by default)
- Encryption key is device-specific (not synced)
- Settings stored in encrypted_shared_preferences

### 4. Transparent Code
- All code on GitHub (open-source)
- No closed-source binaries
- Community code review enabled
- Reproducible builds planned

### 5. Minimal Permissions
- Android: VPN permission only
- iOS: VPN configuration access only
- No camera, microphone, contacts, location, etc.

## Security Limitations

This app protects against:
- ✅ ISP monitoring of visited websites
- ✅ Regional censorship (content blocking)
- ✅ Man-in-the-middle attacks on public WiFi
- ✅ IP address leaks

This app does NOT protect against:
- ❌ Application-level leaks (DNS, WebRTC)
  - *Mitigation*: Always use secure DNS (DOH/DOT)
  - *Mitigation*: Disable WebRTC in browsers
- ❌ VPN provider snooping
  - *Mitigation*: Only use trusted providers
  - *Mitigation*: Use no-log VPN providers
- ❌ Compromised VPN server
  - *Mitigation*: Review server configuration source
  - *Mitigation*: Speed test results indicate anomalies
- ❌ Malware on device
  - *Mitigation*: Keep OS and apps updated
  - *Mitigation*: Use reputable antivirus

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

### Kill Switch
- Not implemented in v1.0 (Phase 5 feature)
- **Impact**: If app crashes, user traffic may leak outside VPN
- **Mitigation**: Connection status is real-time, reconnect is instant

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
- Check file integrity: SHA256 checksums provided for APK/IPA
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

**Last Updated**: 2026-01-15  
**Maintained By**: Blackout Kit Security Team  
**Contact**: security@blackout-kit.dev
