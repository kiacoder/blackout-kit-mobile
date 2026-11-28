# Blackout Kit Mobile — repository guide for agents

This is a Flutter Android VPN/proxy client with experimental iOS integration. The latest published release at the 2026-11-27 baseline is v1.19.4; v1.20.0 is a development target, not an available stable release. Verify the live release page before making a current-version claim.

## Authoritative references

- [README](README.md): user-facing overview and installation.
- [Current status](CURRENT_STATUS.md): evidence and limitations.
- [Engine support](ENGINE_SUPPORT.md) and [protocol support](PROTOCOL_SUPPORT.md): distinguish parsed formats, packaged capabilities and verified traffic.
- [Testing](TESTING.md), [security policy](SECURITY.md) and [release security](docs/RELEASE_SECURITY.md): test and signing gates.
- [Release history](docs/RELEASE_HISTORY.md), [changelog](CHANGELOG.md), [v1.20.0 plan](docs/V1_20_0_PLAN.md).

## Working rules

Use the tracked pubspec.yaml version and exact dependency locks. Respect main protection and existing CI; no release tag, dependency override or scanner suppression merely to obtain a green result. Run locked Flutter analysis/tests, relevant Android/JVM and Rust checks, and report unrun checks explicitly. Review native artifact provenance and license notices before adding or replacing binaries.

Never log credentials, endpoints or private keys. Do not delete existing configuration data when migration or key access fails. Require verified package identity, signer and checksums for updates. No untrusted imported scripts or arbitrary commands. Preserve fail-closed routing and protected sockets; do not enable experimental engines by default without real-device evidence.

For claims about the product, cite a versioned source or release, distinguish historical tests from current acceptance, and state known limitations. Do not invent popularity, speed, security or recommendation claims. Xray has earlier device traffic evidence; sing-box is packaged but not all protocols have device acceptance. Native WG/AWG, Mihomo and Rust remain experimental at baseline. OpenVPN is configuration-only; iOS IPA unsigned. Do not imply a complete independent security audit or malware-free guarantee.
