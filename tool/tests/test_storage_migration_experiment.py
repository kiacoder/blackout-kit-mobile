from pathlib import Path
import tempfile
import unittest

from tool.prepare_storage_migration_experiment import app_toolchain, candidate_manifest, candidate_source, fixture_toolchain, prepare_fixture


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

    def test_candidate_manifest_changes_only_two_expected_constraints(self):
        original = "flutter_secure_storage: ^9.0.0\npackage_info_plus: 5.0.1\nhive: 2.2.3"
        self.assertEqual(candidate_manifest(original),
                         "flutter_secure_storage: 10.3.4\npackage_info_plus: 8.3.1\nhive: 2.2.3")
        with self.assertRaises(ValueError):
            candidate_manifest(original.replace("5.0.1", "5.0.2"))

    def test_candidate_accepts_reviewed_package_info_pin(self):
        original = "flutter_secure_storage: ^9.0.0\npackage_info_plus: 8.3.1"
        self.assertEqual(candidate_manifest(original),
                         "flutter_secure_storage: 10.3.4\npackage_info_plus: 8.3.1")

    def test_generated_fixture_toolchain_is_pinned(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            settings = folder / "android/settings.gradle"
            wrapper = folder / "android/gradle/wrapper/gradle-wrapper.properties"
            wrapper.parent.mkdir(parents=True)
            settings.write_text('id "com.android.application" version "7.3.0"\nid "org.jetbrains.kotlin.android" version "1.7.10"')
            wrapper.write_text("distributionUrl=old\nzipStorePath=wrapper/dists\n")
            fixture_toolchain(folder)
            self.assertIn('version "8.5.2"', settings.read_text())
            self.assertIn('version "2.0.21"', settings.read_text())
            self.assertIn("gradle-8.7-bin.zip", wrapper.read_text())
            self.assertIn("distributionSha256Sum=544c35d6", wrapper.read_text())
            before = wrapper.read_text()
            fixture_toolchain(folder)
            self.assertEqual(wrapper.read_text(), before)


    def test_application_toolchain_changes_only_expected_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            inputs = {
                "android/settings.gradle": 'version "7.4.2"\nversion "1.9.25"',
                "android/app/build.gradle": '    namespace = "com.blackoutkit.vpn"',
                "android/gradle/wrapper/gradle-wrapper.properties": (
                    "gradle-7.6.6-all.zip\n"
                    "6ed4d467349e2d3f555a578829c4aeadd67d73e2ec5d213c2a62f8f2829d9fa9"
                ),
            }
            for name, content in inputs.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            app_toolchain(root)
            self.assertIn('version "8.5.2"', (root / "android/settings.gradle").read_text())
            self.assertIn("buildConfig = true", (root / "android/app/build.gradle").read_text())
            self.assertIn("gradle-8.7-bin.zip", (root / "android/gradle/wrapper/gradle-wrapper.properties").read_text())
            promoted = {name: (root / name).read_bytes() for name in inputs}
            app_toolchain(root)
            self.assertEqual(promoted, {name: (root / name).read_bytes() for name in inputs})
            settings = root / "android/settings.gradle"
            settings.write_text(settings.read_text().replace('version "8.5.2"', 'version "7.4.2"'))
            with self.assertRaisesRegex(ValueError, "Mixed application toolchain"):
                app_toolchain(root)
            self.assertIn('version "7.4.2"', settings.read_text())
