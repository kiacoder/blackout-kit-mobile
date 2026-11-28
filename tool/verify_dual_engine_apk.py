"""Verify the private ARM dual-engine APK, never the production package."""
import argparse
import json
from pathlib import Path
import subprocess
from tool.stage_openvpn_candidate import verify as verify_openvpn
from tool.verify_mihomo_apk import verify as verify_mihomo

PACKAGE = "com.blackoutkit.vpn.dualenginetest"

def verify(apk, openvpn, mihomo, badging):
    first = verify_openvpn(apk, openvpn, badging, package=PACKAGE)
    second = verify_mihomo(apk, mihomo, badging, package=PACKAGE)
    if first["apkSha256"] != second["apkSha256"]:
        raise ValueError("APK changed during verification")
    return {"package": PACKAGE, "apkSha256": first["apkSha256"],
            "openvpn": first["sha256"], "mihomo": second["sha256"],
            "scope": "private dual engine packaging, not physical device acceptance"}

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apk", type=Path, required=True)
    p.add_argument("--aapt", required=True)
    args = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    badging = subprocess.check_output([args.aapt, "dump", "badging", str(args.apk)], text=True, encoding="utf-8")
    print(json.dumps(verify(args.apk,
        json.loads((root / ".cache/openvpn3-jni/SHA256.json").read_text()),
        json.loads((root / ".cache/mihomo-jni/PROVENANCE.json").read_text()),
        badging), indent=2))
