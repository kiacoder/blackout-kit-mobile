from pathlib import Path
import tempfile
import unittest

from tool.prepare_storage_migration_experiment import candidate_source, prepare_fixture


class StorageMigrationExperimentTests(unittest.TestCase):
    def test_options_keep_reset_disabled(self):
        legacy = "encryptedSharedPreferences: true,\nresetOnError: false,"
        for backup in (True, False):
            result = candidate_source(legacy, backup)
            self.assertIn("resetOnError: false,", result)
            self.assertIn("migrateOnAlgorithmChange: true,", result)
            self.assertIn(f"migrateWithBackup: {str(backup).lower()},", result)
            self.assertNotIn("encryptedSharedPreferences:", result)

    def test_unknown_options_rejected(self):
        with self.assertRaises(ValueError):
            candidate_source("encryptedSharedPreferences: true,")
        with self.assertRaises(ValueError):
            candidate_source("resetOnError: false,")

    def test_production_package_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            gradle = folder / "android/app/build.gradle"
            gradle.parent.mkdir(parents=True)
            original = 'applicationId = "com.blackoutkit.vpn"'
            gradle.write_text(original)
            with self.assertRaises(ValueError):
                prepare_fixture(folder, "candidate")
            self.assertEqual(gradle.read_text(), original)
