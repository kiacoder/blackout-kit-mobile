import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tool.audit_native_candidate_download import APK_NAME, audit, comparison_records
from tool.verify_native_candidate_apk import ABIS, ENGINES, PACKAGE, verify_apk


class CandidateDownloadTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.apk = self.root / APK_NAME
        self.comparison = self.root / "replica-comparison.json"
        self.report = {"scope": "independent byte equality; not device acceptance",
                       "results": []}
        with zipfile.ZipFile(self.apk, "w") as archive:
            for engine in ENGINES:
                hashes = {}
                for abi in ABIS:
                    data = f"{abi}:{engine}".encode()
                    archive.writestr(f"lib/{abi}/lib{engine}.so", data)
                    hashes[abi] = hashlib.sha256(data).hexdigest()
                self.report["results"].append({"engine": engine, "sha256": hashes})
        self.comparison.write_text(json.dumps(self.report), encoding="utf-8")
        self.digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        (self.root / "SHA256SUMS").write_text(f"{self.digest}  {APK_NAME}\n", encoding="ascii")
        self.packaging = self.root / "packaging.json"
        self.packaging.write_text(json.dumps(
            verify_apk(self.apk, comparison_records(self.report))), encoding="utf-8")

    def run_audit(self):
        return audit(self.root, self.comparison, "aapt", "apksigner")

    @patch("tool.audit_native_candidate_download.subprocess.check_output",
           return_value=f"package: name='{PACKAGE}' versionCode='1'\napplication-debuggable\n")
    @patch("tool.audit_native_candidate_download.subprocess.run")
    def test_verified_download(self, signer, badging):
        self.assertEqual(self.run_audit()["apk_sha256"], self.digest)
        signer.assert_called_once()
        badging.assert_called_once()

    @patch("tool.audit_native_candidate_download.subprocess.run")
    def test_tampered_apk_rejected_before_signature_check(self, signer):
        with self.apk.open("ab") as stream:
            stream.write(b"tampered")
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.run_audit()
        signer.assert_not_called()

    @patch("tool.audit_native_candidate_download.subprocess.run")
    def test_packaging_report_mismatch(self, signer):
        self.packaging.write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Packaging report disagrees"):
            self.run_audit()
        signer.assert_not_called()

    def test_duplicate_engine_rejected(self):
        self.report["results"].append(self.report["results"][0])
        with self.assertRaisesRegex(ValueError, "duplicate engine"):
            comparison_records(self.report)

    def test_missing_abi_rejected(self):
        self.report["results"][0]["sha256"].pop(next(iter(ABIS)))
        with self.assertRaisesRegex(ValueError, "ABI inventory"):
            comparison_records(self.report)

    @patch("tool.audit_native_candidate_download.subprocess.check_output",
           return_value="package: name='com.blackoutkit.vpn' versionCode='1'\napplication-debuggable\n")
    @patch("tool.audit_native_candidate_download.subprocess.run")
    def test_production_package_rejected(self, _signer, _badging):
        with self.assertRaisesRegex(ValueError, "isolated debuggable package"):
            self.run_audit()
