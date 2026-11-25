# Isolated Android secure-storage migration fixture

This is a synthetic debug-only test, not an application upgrade or release artifact.
All three APKs use the separate package `com.blackoutkit.storagefixture`. The legacy
fixture uses 9.2.4 and creates a random key and a single synthetic encrypted Hive
record. Both candidates use 10.3.4 with migration enabled and automatic reset
disabled. One enables migration backups; the other disables them.

Use an authorized disposable Android device or emulator. Verify the artifact hashes
against SHA256SUMS and the package identity/signing fingerprints before installation.
Do not install these fixtures over the real application. The test is intentionally
manual until the build and device behavior have both been validated.

For each candidate separately, begin with the fixture package absent (remove only
the disposable fixture app if you previously installed it). Install legacy.apk,
open it, and require STORAGE_LEGACY_PASS. Close the fixture, then install the
selected candidate APK as an update, retaining its data. Open it and require
STORAGE_MIGRATION_PASS. Force-stop and reopen it; require the same result. Repeat
the entire sequence from a fresh legacy fixture for the other candidate.

A failure or missing marker means the migration has not passed. Do not clear
production app data or extract keys. A passing fixture is evidence for this
specific synthetic migration, not proof of all upgrade or crash-recovery paths.
Record the Android API level, APK hashes, backup setting, and outcomes. Test
interrupted migration separately before approving any production upgrade.

Upstream reports an issue involving the exact legacy-to-candidate migration with
backup enabled (issue #1289); neither backup setting is approved by this fixture
until device results are available:
https://github.com/juliansteenbakker/flutter_secure_storage/issues/1289


Automated acceptance now runs on disposable hosted API 24 and 34
emulators. The runner verifies SHA256SUMS, package versions and
shared signer before installing, refuses a pre-existing fixture,
checks each upgrade and restart, and removes only the fixture it
installed. Actual device outcomes are recorded independently of
APK compilation. For local artifact-only verification, invoke
python tool/run_storage_migration_acceptance.py with --folder,
--aapt, --apksigner and --output. To execute on a disposable
emulator, also pass --adb and its explicit --serial.
