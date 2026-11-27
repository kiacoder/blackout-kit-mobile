import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.stage_openvpn_candidate import ABIS, LIB, PACKAGE, verify


class OpenVpnCandidateTests(unittest.TestCase):
    def test_packaging_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / "test.apk"
            files = {f"lib/{abi}/{LIB}": abi.encode() for abi in ABIS}
            records = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
            badging = f"package: name='{PACKAGE}' versionCode='1'\napplication-debuggable\n"

            def write(members):
                with zipfile.ZipFile(apk, "w") as archive:
                    for name, data in members.items():
                        archive.writestr(name, data)

            write(files)
            self.assertEqual(verify(apk, records, badging)["sha256"], records)
            with self.assertRaises(ValueError):
                verify(apk, records, badging.replace(PACKAGE, "com.blackoutkit.vpn"))
            with self.assertRaises(ValueError):
                verify(apk, {}, badging)
            name = next(iter(files))
            for bad in ({}, {**files, name: b"changed"}, {**files, f"lib/x86/{LIB}": b"extra"}):
                write(bad)
                with self.assertRaises(ValueError):
                    verify(apk, records, badging)
