import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tool.verify_native_candidate_apk import stage, verify_apk
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

    @patch.dict("os.environ", {"GITHUB_ACTIONS": "false"}, clear=True)
    def test_non_ci_stage_refused(self):
        with self.assertRaisesRegex(ValueError, "disposable Linux"):
            stage(self.root, self.root / "replicas")
