# Android toolchain candidate security review

Reviewed 2026-11-25. Evidence: GitHub Actions run
[45443595453](https://github.com/kiacoder/blackout-kit-mobile/actions/runs/45443595453),
artifact 14945658744, candidate commit 37be23c6394a5f7c41d082861833750e28d8bf04.
This is an earlier test-only build, not the current PR or a production release.

## Verified evidence

- Recomputed SHA-256 of all three APKs, APK_INVENTORY.json and six evidence files; all matched SECURITY_REPORT.json or the inventory.
- ClamAV 1.5.4: three scanned APKs, zero infected files. No malware-free guarantee.
- MobSF: universal APK static analysis only, score 46/100, four high findings, ten warnings, zero detected trackers. A score is not an acceptance verdict.
- VirusTotal: all three hash records report not-configured. No verdict or upload claimed.
- APKs signed with a debug certificate for testing. Production signing remains a separate gate.

## High findings and disposition

| Finding | Assessment / next action |
| --- | --- |
| Debug signing | Expected on this non-tag run; must fail production publication. |
| Cleartext exceptions | Existing Android policy defaults to no cleartext; only local exceptions were present. Removed the unused 10.111.222.1 HTTP exception on PR20 after checking tracked references; retain loopback for local proxy compatibility. Retest on device. Native network stacks may not honor Android's Java HTTP policy. |
| Minimum API 24 | Compatibility policy, not proof that every API 24 device is vulnerable. Older unsupported systems carry real risk; raising minimum API requires explicit compatibility decision and test coverage. |
| CBC with PKCS padding | Located in flutter_secure_storage 9.2.4 dependency code. SecureKeyStore requests encryptedSharedPreferences, but static presence alone cannot establish whether the CBC implementation is reachable. Review plugin migration, key preservation and actual device path before changing storage options. |

## Warning triage (not cleared)

- Platform CA trust and exported AndroidX ProfileInstallReceiver protected by android.permission.DUMP: verify merged manifest and permission protections on supported Android.
- Temporary files include native config checks and EngineRunner. Private storage and bounded cleanup are intentional; interrupted-process residue and deletion failures need lifecycle tests.
- External storage, raw SQLite queries, SHA-1 and non-cryptographic random calls are reported in obfuscated dependency classes; map to exact dependencies and call paths before assigning exploitability.
- IP literals include local interface/loopback addresses. Verify remaining paths and logging; literal IP detection is not itself evidence of disclosure.
- Hardcoded-secret heuristics require provenance/context review. Do not publish raw scanner strings.
- Native shared library mitigations and provenance require separate review. Do not close security acceptance based on the static report.

## Refreshed experiment

Merged PR20 commit 0638ded into isolated toolchain branch at f6925cac3cda7e9065d3d9a4607954bd59f0f489. Compared to that PR commit, only the three candidate Android build files differ. The original PR pins remain unchanged.

- [Refreshed Tests run](https://github.com/kiacoder/blackout-kit-mobile/actions/runs/45562485870)
- [Refreshed APK/iOS build run](https://github.com/kiacoder/blackout-kit-mobile/actions/runs/45562490487)

Both were in progress at inspection. Re-run the network policy change on the candidate before promotion. No merge to main or release authorized by this review. Local Google Maven resolution, final artifact review, native traffic and upgrade/device acceptance remain open.


## Native binary and configuration follow-up (2026-11-25)

Earlier universal APK native analysis covers nine libraries in each of
ARM64 and ARMv7. All report NX and position independence; full RELRO
is reported where applicable (Flutter/Dart exceptions). Both ABIs of
libgojni, libsingbox, libtun2socks and libblackout_core lack conventional
C stack-canary and fortified-call signatures. fdlauncher has canaries
but no fortified calls detected. Go/Rust runtime/code generation is not
equivalent to C; inspect actual CGO, unsafe FFI, source provenance and
release ELF properties. Do not add artificial symbol references to
improve the score. fdlauncher now explicitly requests stack protector,
FORTIFY_SOURCE=2, format checks, full RELRO and non-executable stack;
debug build succeeded and compiler/linker flags were verified. Release
binary and MobSF confirmation are still required.

Replaced fixed credential-bearing subprocess config paths with unique
app-private session files owned by TransientEngineConfig. Current
config is mandatory for start; old files cannot be selected. Active
file stays until the associated engine is stopped; failed deletion
retains the handle for retry. Probe validation rejection and launch
I/O failure attempt cleanup. No secure-erase guarantee; previous
fixed-name files and crash residue need separately validated cleanup.
Cross-engine admission and unresolved checker processes remain open.

Three new ownership tests passed. Both refreshed f6925ca toolchain
Tests and APK/iOS builds succeeded; this does not validate the latest
configuration cleanup commit or device behavior. Artifact 14999290623
is available for fresh report review. No revised MobSF score claimed.
