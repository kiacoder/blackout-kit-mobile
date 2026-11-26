# Multi-engine roadmap (not a completion claim)

1. Establish reproducible Flutter/Android/native toolchain and device baseline. Run all
   new and existing tests; fix regressions before releasing. Review native supply-chain
   provenance and notices. Add translations/widget tests for export UX.
2. Pin/reconcile sing-box Android/iOS versions; exact-feature native validation and
   Xray upgrades with known working transport fixtures. Do not mix incompatible schemas.
3. Define runtime adapter ownership/cancellation/stats/protection interface based on
   actual backend APIs. Add engine-specific full-document persistence/UI without losing
   existing URI profiles. Include credentials vault, migration and rollback tests.
4. Mihomo first-class runtime: YAML/groups/providers/DNS/TUN, protected sockets,
   authenticated loopback controller, selection, health/failover and update lifecycle.
5. AWG official backend and verified AWG1/1.5/2 grammar/server interoperability;
   separate Go runtime if needed. Native WG backend including QR, routes and lockdown.
6. OpenVPN backend after API/license review, auth/cert callbacks and unsafe-directive
   policy; never run imported scripts by default.
7. Authorized three-server inventory, backups and additive deployment. Generate real
   client profiles and verify each before consolidated v2rayN/companion delivery.
8. Full configuration factory in-app: lossless JSON/YAML/raw docs, metadata archives,
   QR/file batches, conservative explicit conversions and subscription update policy.
9. Device/performance/security matrix and production burn-in; publish only after
   explicit release authorization. No push or public release performed here.
