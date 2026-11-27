"""Private debug staging and exact APK-byte verification, not release approval."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

from tool.check_android_artifact import validate

ROOT = Path(__file__).resolve().parents[1]
ABIS = ("arm64-v8a", "armeabi-v7a")
LIB = "libopenvpn-candidate.so"
PACKAGE = "com.blackoutkit.vpn.openvpntest"
SYMBOLS = tuple("Java_com_blackoutkit_vpn_OpenVpnNativeBridge_native" + name
                for name in ("Create", "RunV3", "Reconnect", "Cancel", "Release"))


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def stage(build, output):
    if output.exists():
        raise ValueError("Existing staging must be reviewed; will not overwrite")
    records = {}
    for abi in ABIS:
        source = build / abi / LIB
        validate(source.read_bytes(), abi, 24, required_symbols=SYMBOLS)
        records[f"lib/{abi}/{LIB}"] = sha(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as tmp:
        pending = Path(tmp) / "staged"
        for abi in ABIS:
            target = pending / abi / LIB
            target.parent.mkdir(parents=True)
            shutil.copy2(build / abi / LIB, target)
            if sha(target) != records[f"lib/{abi}/{LIB}"]:
                raise ValueError("Candidate changed during staging")
        (pending / "SHA256.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
        pending.rename(output)
    return records


def verify(apk, records, badging):
    required = {f"lib/{abi}/{LIB}" for abi in ABIS}
    if set(records) != required:
        raise ValueError("Wrong candidate inventory")
    if not badging.startswith(f"package: name='{PACKAGE}' ") or "application-debuggable" not in badging.splitlines():
        raise ValueError("Wrong debug package")
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK members")
        if {name for name in names if name.endswith("/" + LIB)} != required:
            raise ValueError("Wrong packaged candidate inventory")
        for name, digest in records.items():
            with archive.open(name) as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                    raise ValueError("Candidate bytes differ")
    return {"package": PACKAGE, "apkSha256": sha(apk), "sha256": records,
            "scope": "private packaging only, Android execution not tested"}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--stage", action="store_true")
    p.add_argument("--apk", type=Path)
    p.add_argument("--aapt")
    args = p.parse_args()
    output = ROOT / ".cache/openvpn3-jni"
    if args.stage:
        if args.apk or args.aapt:
            p.error("Stage and verify separately")
        print(json.dumps(stage(ROOT / ".cache/openvpn3-android", output), indent=2))
    elif args.apk and args.aapt:
        badging = subprocess.check_output([args.aapt, "dump", "badging", str(args.apk)], text=True, encoding="utf-8")
        print(json.dumps(verify(args.apk, json.loads((output / "SHA256.json").read_text()), badging), indent=2))
    else:
        p.error("Provide --stage or --apk and --aapt")


if __name__ == "__main__":
    main()
