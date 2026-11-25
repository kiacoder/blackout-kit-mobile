import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from tool.release_security import inventory, package_identity, scanner_summary, signer_digest, verify_apks

class ReleaseSecurityTests(unittest.TestCase):
    def apk(self, folder, abi='arm64-v8a', extra=None):
        path = folder / 'blackout-kit-test-arm64-v8a.apk'
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('AndroidManifest.xml', b'manifest')
            z.writestr('classes.dex', b'dex')
            for lib in ('libflutter.so','libapp.so','libgojni.so','libblackout_core.so'):
                z.writestr(f'lib/{abi}/{lib}', b'lib')
            if extra: z.writestr(extra, b'unexpected')
        return path

    def test_valid_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(len(inventory(self.apk(Path(d)), {'arm64-v8a'})), 4)

    def test_experimental_library_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ('libblackout-tunnels.so', 'libprocess_guard.so', 'libprocess_guard_fixture.so'):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    inventory(self.apk(Path(d), extra=f'lib/arm64-v8a/{name}'), {'arm64-v8a'})

    def test_wrong_abi_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):
                inventory(self.apk(Path(d)), {'armeabi-v7a'})

    def test_signer_count(self):
        line = 'Signer #1 certificate SHA-256 digest: ' + 'a'*64
        report = 'Verifies\nNumber of signers: 1\n' + line
        self.assertEqual(signer_digest(report), 'a'*64)
        for invalid in (line, report + '\n' + line.replace('#1','#2'),
                        report.replace('signers: 1','signers: 2'),
                        report.replace('certificate SHA-256','public key SHA-256')):
            with self.assertRaises(ValueError):
                signer_digest(invalid)

    def test_numbered_leaf_certificate(self):
        report = ('Verifies\nNumber of signers: 1\n'
                  'Signer #1 certificate #1 SHA-256 digest: ' + 'AB'*32 + '\n'
                  'Signer #1 public key SHA-256 digest: ' + 'cd'*32 + '\n')
        self.assertEqual(signer_digest(report), 'ab'*32)

    def test_distribution_package_identity(self):
        report = "package: name='com.blackoutkit.vpn' versionCode='123' versionName='1.2.3'"
        self.assertEqual(package_identity(report), {
            'package': 'com.blackoutkit.vpn', 'version_code': '123', 'version_name': '1.2.3'})

    def test_distribution_rejects_experiment_and_debuggable(self):
        report = "package: name='com.blackoutkit.vpn' versionCode='123' versionName='1.2.3'"
        for invalid in (report.replace('.vpn', '.vpn.nativetest'),
                        report + '\napplication-debuggable',
                        report + '\n' + report, 'no package'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                package_identity(invalid)

    def test_tag_requires_existing_certificate(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'ANDROID_RELEASE_CERT_SHA256'):
                verify_apks(Path(d), 'apksigner', True, '')

class ScannerEvidenceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.folder = Path(temp.name)
        self.records = [
            {"name": "app-" + abi + ".apk", "sha256": digit * 64}
            for abi, digit in (("arm64-v8a", "a"), ("armeabi-v7a", "b"), ("universal", "c"))
        ]
        self.vt = [{"file": r["name"], "sha256": r["sha256"], "status": "unknown-file"}
                   for r in self.records]
        self.write("VIRUSTOTAL_REPORT.json", self.vt)
        self.write("MOBSF_STATUS.json", {"status": "completed-review-required"})
        self.mobsf = {"sha256": "c" * 64, "appsec": {
            "high": [{"title": "fixture rule", "section": "code", "description": "synthetic secret value"}], "warning": [], "info": [], "secure": [], "hotspot": [],
            "security_score": 46,
        }}
        self.write("MOBSF_REPORT.json", self.mobsf)
        (self.folder / "CLAMAV_REPORT.txt").write_text("Scanned files: 3\nInfected files: 0\n")

    def write(self, name, value):
        (self.folder / name).write_text(json.dumps(value))

    def test_unknown_virustotal_is_not_clean(self):
        result = scanner_summary(self.folder, self.records)
        self.assertTrue(result["review_required"])
        self.assertEqual(result["virustotal"][0]["status"], "unknown-file")
        self.assertEqual(result["mobsf"]["counts"]["high"], 1)

    def test_compact_findings_do_not_copy_descriptions(self):
        first = scanner_summary(self.folder, self.records)["mobsf"]["findings"][0]
        self.assertEqual(first["title"], "fixture rule")
        self.assertNotIn("synthetic secret value", json.dumps(first))
        self.mobsf["appsec"]["high"][0]["description"] = "different affected files"
        self.write("MOBSF_REPORT.json", self.mobsf)
        second = scanner_summary(self.folder, self.records)["mobsf"]["findings"][0]
        self.assertEqual(first["rule_sha256"], second["rule_sha256"])
        self.assertNotEqual(first["evidence_sha256"], second["evidence_sha256"])

    def test_malformed_finding_rejected(self):
        self.mobsf["appsec"]["high"][0]["description"] = None
        self.write("MOBSF_REPORT.json", self.mobsf)
        with self.assertRaisesRegex(ValueError, "finding fields"):
            scanner_summary(self.folder, self.records)

    def test_clamav_partial_scan_or_detection_rejected(self):
        for value in ("Scanned files: 2\nInfected files: 0", "Scanned files: 3\nInfected files: 1",
                      "Scanned files: 3\nInfected files: 0\nTotal errors: 1"):
            (self.folder / "CLAMAV_REPORT.txt").write_text(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                scanner_summary(self.folder, self.records)

    def test_virustotal_mismatched_digest_rejected(self):
        self.vt[0]["sha256"] = "0" * 64
        self.write("VIRUSTOTAL_REPORT.json", self.vt)
        with self.assertRaisesRegex(ValueError, "exact APK"):
            scanner_summary(self.folder, self.records)

    def test_mobsf_stale_report_rejected(self):
        self.mobsf["sha256"] = "a" * 64
        self.write("MOBSF_REPORT.json", self.mobsf)
        with self.assertRaisesRegex(ValueError, "universal APK"):
            scanner_summary(self.folder, self.records)
        self.write("MOBSF_STATUS.json", {"status": "not-configured"})
        with self.assertRaisesRegex(ValueError, "stale report"):
            scanner_summary(self.folder, self.records)

if __name__ == '__main__':
    unittest.main()
