import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.stage_mihomo import ABIS, PIN, VERSION, GO
from tool.stage_openvpn_candidate import LIB
from tool.verify_dual_engine_apk import PACKAGE, verify


class DualEngineApkTests(unittest.TestCase):
    def test_dual_inventory_and_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "dual.apk"
            openvpn = {f"lib/{abi}/{LIB}": f"openvpn-{abi}".encode() for abi in ABIS}
            mihomo = {f"lib/{abi}/libmihomo.so": f"mihomo-{abi}".encode() for abi in ABIS}
            files = {**openvpn, **mihomo, **{
                f"lib/{abi}/{name}": b"fixture" for abi in ABIS
                for name in ("libtun2socks.so", "libfdlauncher.so")
            }}
            records = {name: hashlib.sha256(data).hexdigest() for name, data in openvpn.items()}
            manifest = {"artifacts": [
                {"abi": abi, "sourceCommit": PIN, "version": VERSION, "go": GO,
                 "sha256": hashlib.sha256(mihomo[f"lib/{abi}/libmihomo.so"]).hexdigest()}
                for abi in ABIS]}
            badging = f"package: name='{PACKAGE}' versionCode='1'\napplication-debuggable\n"

            def write(members):
                with zipfile.ZipFile(apk, "w") as archive:
                    for name, data in members.items():
                        archive.writestr(name, data)

            write(files)
            self.assertEqual(verify(apk, records, manifest, badging)["package"], PACKAGE)
            for package in ("com.blackoutkit.vpn", "com.blackoutkit.vpn.openvpntest",
                            "com.blackoutkit.vpn.mihomotest"):
                with self.assertRaises(ValueError):
                    verify(apk, records, manifest, badging.replace(PACKAGE, package))
            for name in (next(iter(openvpn)), next(iter(mihomo)), "lib/arm64-v8a/libtun2socks.so"):
                write({key: value for key, value in files.items() if key != name})
                with self.assertRaises(ValueError):
                    verify(apk, records, manifest, badging)
