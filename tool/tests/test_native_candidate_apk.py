import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tool.verify_native_candidate_apk import PREFIX, stage, verify_apk
from tool.build_pinned_go_engines import ABIS, ENGINES


class CandidateApkTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.apk = self.root / "fixture.apk"
        self.files = {
            f"lib/{abi}/lib{engine}.so": f"{abi}:{engine}".encode()
            for abi in ABIS for engine in ENGINES
        }
        self.records = {
            name: hashlib.sha256(data).hexdigest()
            for name, data in self.files.items()
        }

    def write_apk(self, files):
        with zipfile.ZipFile(self.apk, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)

    def test_exact_candidate_inventory(self):
        self.write_apk(self.files)
        self.assertEqual(verify_apk(self.apk, self.records)["sha256"], self.records)

    def test_changed_candidate_rejected(self):
        files = dict(self.files)
        files[next(iter(files))] = b"tampered"
        self.write_apk(files)
        with self.assertRaisesRegex(ValueError, "bytes differ"):
            verify_apk(self.apk, self.records)

    def test_missing_and_extra_abi_rejected(self):
        files = dict(self.files)
        del files[next(iter(files))]
        self.write_apk(files)
        with self.assertRaisesRegex(ValueError, "Missing candidate"):
            verify_apk(self.apk, self.records)
        self.write_apk({**self.files, "lib/x86/libexample.so": b"extra"})
        with self.assertRaisesRegex(ValueError, "Unexpected native ABI"):
            verify_apk(self.apk, self.records)

    def test_unknown_abi_rejected(self):
        self.write_apk({**self.files, "lib/riscv64/libexample.so": b"extra"})
        with self.assertRaisesRegex(ValueError, "Unexpected native ABI"):
            verify_apk(self.apk, self.records)

    @patch.dict("os.environ", {"GITHUB_ACTIONS": "true", "RUNNER_OS": "Linux"})
    @patch("tool.verify_native_candidate_apk.subprocess.check_output", return_value="")
    def test_tampered_last_candidate_leaves_all_slots_unchanged(self, _status):
        replicas = self.root / "replicas"
        slots = []
        for member, data in self.files.items():
            _, abi, name = member.split("/")
            slot = self.root / PREFIX / abi / name
            slot.parent.mkdir(parents=True, exist_ok=True)
            slot.write_bytes(b"baseline")
            slots.append(slot)
            source = replicas / f"native-go-{name[3:-3]}-1" / abi / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(data)
        source.write_bytes(b"tampered")
        with patch("tool.verify_native_candidate_apk.expected", return_value=self.records):
            with self.assertRaisesRegex(ValueError, "changed after comparison"):
                stage(self.root, replicas)
        self.assertTrue(all(slot.read_bytes() == b"baseline" for slot in slots))

    @patch.dict("os.environ", {"GITHUB_ACTIONS": "false"}, clear=True)
    def test_non_ci_stage_refused(self):
        with self.assertRaisesRegex(ValueError, "disposable Linux"):
            stage(self.root, self.root / "replicas")
