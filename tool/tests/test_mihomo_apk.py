import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.stage_mihomo import ABIS, PIN, VERSION, GO
from tool.verify_mihomo_apk import PACKAGE, verify


class MihomoApkTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.apk = Path(temp.name) / "test.apk"
        self.files = {f"lib/{abi}/libmihomo.so": abi.encode() for abi in ABIS}
        self.files.update({f"lib/{abi}/{lib}": b"fixture" for abi in ABIS
                           for lib in ("libtun2socks.so", "libfdlauncher.so")})
        self.manifest = {"artifacts": [
            {"abi": abi, "sourceCommit": PIN, "version": VERSION, "go": GO,
             "sha256": hashlib.sha256(abi.encode()).hexdigest()} for abi in ABIS]}
        self.badging = f"package: name='{PACKAGE}' versionCode='1'\napplication-debuggable\n"

    def write(self, files):
        with zipfile.ZipFile(self.apk, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)

    def test_exact_bytes(self):
        self.write(self.files)
        self.assertEqual(verify(self.apk, self.manifest, self.badging)["package"], PACKAGE)

    def test_normal_package_rejected(self):
        self.write(self.files)
        with self.assertRaises(ValueError):
            verify(self.apk, self.manifest, self.badging.replace(PACKAGE, "com.blackoutkit.vpn"))

    def test_missing_changed_or_extra_engine_rejected(self):
        name = next(iter(self.files))
        for files in ({}, {**self.files, name: b"changed"},
                      {**self.files, "lib/x86/libmihomo.so": b"extra"}):
            self.write(files)
            with self.assertRaises(ValueError):
                verify(self.apk, self.manifest, self.badging)

    def test_missing_bridge_rejected(self):
        files = dict(self.files)
        del files["lib/arm64-v8a/libfdlauncher.so"]
        self.write(files)
        with self.assertRaises(ValueError):
            verify(self.apk, self.manifest, self.badging)

    def test_duplicate_manifest_rejected(self):
        self.write(self.files)
        self.manifest["artifacts"].append(self.manifest["artifacts"][0])
        with self.assertRaises(ValueError):
            verify(self.apk, self.manifest, self.badging)
