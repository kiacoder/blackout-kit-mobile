import hashlib
import unittest
from unittest.mock import patch

from tool import patch_storage_backup_fixture as migration


class BackupFixturePatchTests(unittest.TestCase):
    def test_unreviewed_source_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unexpected upstream"):
            migration.patched_source(b"unreviewed")

    def test_expected_anchors_and_legacy_guard(self):
        raw = "\n".join((migration.OLD_CALL, migration.OLD_METHOD, migration.ANCHOR)).encode()
        with patch.object(migration, "UPSTREAM_SHA256", hashlib.sha256(raw).hexdigest()):
            result = migration.patched_source(raw).decode()
        self.assertIn("canSkipMarkerlessMigration(configSource)", result)
        self.assertIn("NamespacedConfigSource configSource", result)
        self.assertIn("config.shouldMigrateWithBackup()", result)
        self.assertIn("!getEncryptedPrefsMigrated(configSource)", result)
        self.assertIn("__androidx_security_crypto_encrypted_prefs_key_keyset__", result)
        self.assertIn("__androidx_security_crypto_encrypted_prefs_value_keyset__", result)
        self.assertLess(result.index("legacyPrefs.contains"), result.index("getCurrentKeyCipher"))

    def test_missing_patch_anchor_rejected_even_with_matching_hash(self):
        raw = migration.OLD_CALL.encode()
        with patch.object(migration, "UPSTREAM_SHA256", hashlib.sha256(raw).hexdigest()):
            with self.assertRaisesRegex(ValueError, "Unexpected migration patch anchor"):
                migration.patched_source(raw)
