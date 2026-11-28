#!/usr/bin/env python3
"""Verify private Mihomo debug APK package identity and exact staged bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

from tool.stage_mihomo import ABIS, PIN, VERSION, GO

PACKAGE = "com.blackoutkit.vpn.mihomotest"


def expected(manifest):
    records = manifest["artifacts"]
    if len(records) != len(ABIS) or {r["abi"] for r in records} != set(ABIS):
        raise ValueError("Incomplete or duplicate candidate inventory")
    result = {}
    for record in records:
        if (record["sourceCommit"], record["version"], record["go"]) != (PIN, VERSION, GO):
            raise ValueError("Unexpected candidate provenance")
        digest = record["sha256"]
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError("Invalid SHA-256")
        result[f'lib/{record["abi"]}/libmihomo.so'] = digest
    return result


def verify(apk, manifest, badging, package=PACKAGE):
    if not badging.startswith(f"package: name='{package}' ") or "application-debuggable" not in badging.splitlines():
        raise ValueError("Expected isolated debuggable Mihomo package")
    records = expected(manifest)
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK members")
        actual = {n for n in names if n.startswith("lib/") and n.endswith("/libmihomo.so")}
        if actual != set(records):
            raise ValueError("Mihomo APK inventory differs from reviewed ABIs")
        for abi in ABIS:
            for library in ("libtun2socks.so", "libfdlauncher.so"):
                if f"lib/{abi}/{library}" not in names:
                    raise ValueError("Missing required bridge library: " + library)
        for name, digest in records.items():
            with archive.open(name) as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                    raise ValueError("Packaged candidate bytes differ: " + name)
    with apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"scope": "private debug packaging only; not device acceptance",
            "package": package, "apkSha256": apk_hash, "sha256": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--aapt", required=True)
    args = parser.parse_args()
    badging = subprocess.check_output([args.aapt, "dump", "badging", str(args.apk)], text=True, encoding="utf-8")
    print(json.dumps(verify(args.apk, json.loads(args.manifest.read_text(encoding="utf-8")), badging), indent=2))


if __name__ == "__main__":
    main()
