import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.run_storage_migration_acceptance import accept, verify_fixtures


class StorageAcceptanceTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        lines = []
        for mode in ("legacy", "candidate", "backup"):
            data = mode.encode()
            (self.folder / (mode + ".apk")).write_bytes(data)
            lines.append(hashlib.sha256(data).hexdigest() + "  " + mode + ".apk")
        (self.folder / "SHA256SUMS").write_text("\n".join(lines))

    def fixture_tool(self, *args, **kwargs):
        if args[0] == "aapt":
            version = "1" if args[-1].endswith("legacy.apk") else "2"
            return "package: name='com.blackoutkit.storagefixture' versionCode='" + version + "'"
        return "Signer #1 certificate SHA-256 digest: " + "a" * 64

    @patch("tool.run_storage_migration_acceptance.run")
    def test_artifact_verification(self, run):
        run.side_effect = self.fixture_tool
        self.assertEqual(len(verify_fixtures(self.folder, "aapt", "signer")), 3)

    @patch("tool.run_storage_migration_acceptance.run")
    def test_tamper_fails_before_install(self, run):
        run.side_effect = self.fixture_tool
        (self.folder / "legacy.apk").write_bytes(b"tamper")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            verify_fixtures(self.folder, "aapt", "signer")
        run.assert_not_called()

    @patch("tool.run_storage_migration_acceptance.run")
    def test_wrong_package_rejected(self, run):
        run.return_value = "package: name='com.blackoutkit.vpn' versionCode='1'"
        with self.assertRaisesRegex(ValueError, "non-fixture"):
            verify_fixtures(self.folder, "aapt", "signer")

    @patch("tool.run_storage_migration_acceptance.run")
    def test_physical_device_refused(self, run):
        with self.assertRaisesRegex(ValueError, "emulator"):
            accept(self.folder, "adb", "physical-123")
        run.assert_not_called()

    @patch("tool.run_storage_migration_acceptance.run")
    def test_existing_fixture_refused(self, run):
        run.side_effect = ["device", "1", "34", "package:com.blackoutkit.storagefixture"]
        with self.assertRaisesRegex(ValueError, "already installed"):
            accept(self.folder, "adb", "emulator-5554")
        self.assertEqual(run.call_count, 4)

    @patch("tool.run_storage_migration_acceptance.run")
    def test_both_upgrades_and_restarts(self, run):
        active = "legacy"
        gate = False
        def fake(*args, **kwargs):
            nonlocal active, gate
            command = args[3:]
            if command == ("get-state",):
                return "device"
            if command[-1] == "ro.kernel.qemu":
                return "1"
            if command[-1] == "ro.build.version.sdk":
                return "34"
            if command[-1] == "ro.product.cpu.abi":
                return "x86_64"
            if command[:3] == ("shell", "pm", "list"):
                return ""
            if command[0] == "install":
                active = Path(command[-1]).stem
                return "Performing Streamed Install\nSuccess"
            if command[:3] == ("shell", "am", "start"):
                return "Status: ok"
            if command[:2] == ("shell", "pidof"):
                return "1234"
            if command[:3] == ("shell", "run-as", "com.blackoutkit.storagefixture"):
                if command[3] == "sha256sum":
                    return "a" * 64 + "  app_flutter/configs_v2.hive"
                if command[3] == "touch":
                    gate = True
                if command[3] == "rm":
                    gate = False
            if command[0] == "logcat":
                if gate:
                    return "STORAGE_KEY_READY"
                return "STORAGE_LEGACY_PASS" if active == "legacy" else "STORAGE_MIGRATION_PASS"
            return "Success"
        run.side_effect = fake
        result = accept(self.folder, "adb", "emulator-5554")
        self.assertEqual(result["results"], {
            "candidate": "upgrade-interruption-and-restart-passed",
            "backup": "upgrade-and-restart-passed",
        })
        commands = [call.args[3:] for call in run.call_args_list]
        self.assertEqual(sum(command[:3] == ("shell", "am", "start") for command in commands), 7)
        self.assertEqual(sum(command[0] == "uninstall" for command in commands), 2)
        self.assertEqual(sum(command == ("logcat", "-c") for command in commands), 7)

        self.assertEqual(sum(command[-2:] == ("touch", "app_flutter/hold_after_key")
                             for command in commands), 1)
        self.assertEqual(sum(command[-2:] == ("sha256sum", "app_flutter/configs_v2.hive")
                             for command in commands), 5)

        run.reset_mock()
        result = accept(self.folder, "adb", "emulator-5554", "backup")
        self.assertEqual(result["results"], {"backup": "upgrade-and-restart-passed"})
        commands = [call.args[3:] for call in run.call_args_list]
        self.assertEqual(sum(command[0] == "install" for command in commands), 2)
        self.assertEqual(sum(command[0] == "uninstall" for command in commands), 1)

        def failed_key(*args, **kwargs):
            if args[3:5] == ("logcat", "-d") and active == "backup":
                return "STORAGE_MIGRATION_FAIL:read_key"
            return fake(*args, **kwargs)

        run.side_effect = failed_key
        result = accept(self.folder, "adb", "emulator-5554", "backup")
        self.assertEqual(result["results"], {
            "backup": "failed at upgrade-launch: Fixture reported migration failure at read_key",
        })


        def changed_file(*args, **kwargs):
            if args[-2:] == ("sha256sum", "app_flutter/configs_v2.hive") and active == "candidate":
                return "b" * 64 + "  app_flutter/configs_v2.hive"
            return fake(*args, **kwargs)

        run.side_effect = changed_file
        result = accept(self.folder, "adb", "emulator-5554", "candidate")
        self.assertEqual(result["results"], {
            "candidate": "failed at interrupt-after-key: Encrypted file changed at interruption boundary",
        })
