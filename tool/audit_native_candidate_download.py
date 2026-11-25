#!/usr/bin/env python3
"""Independently audit downloaded CI candidate APK and replica evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

if __package__:
    from .verify_native_candidate_apk import ABIS, ENGINES, PACKAGE, verify_apk
else:
    from verify_native_candidate_apk import ABIS, ENGINES, PACKAGE, verify_apk

APK_NAME = "standalone-candidates-debug.apk"
DIGEST = re.compile(r"[0-9a-f]{64}")


def comparison_records(report):
    if report.get("scope") != "independent byte equality; not device acceptance":
        raise ValueError("Unexpected replica evidence scope")
    records = {}
    seen = set()
    for result in report["results"]:
        engine = result["engine"]
        if engine not in ENGINES or engine in seen:
            raise ValueError("Unexpected or duplicate engine")
        seen.add(engine)
        if set(result["sha256"]) != set(ABIS):
            raise ValueError("Incomplete replica ABI inventory")
        for abi, digest in result["sha256"].items():
            if not isinstance(digest, str) or not DIGEST.fullmatch(digest):
                raise ValueError("Invalid replica digest")
            records[f"lib/{abi}/lib{engine}.so"] = digest
    if seen != set(ENGINES):
        raise ValueError("Incomplete replica engine inventory")
    return records


def audit(folder, comparison, aapt, apksigner):
    records = comparison_records(json.loads(comparison.read_text(encoding="utf-8")))
    apk = folder / APK_NAME
    checksum = (folder / "SHA256SUMS").read_text(encoding="ascii").strip()
    match = re.fullmatch(r"([0-9a-f]{64})  " + re.escape(APK_NAME), checksum)
    if not match:
        raise ValueError("Unexpected APK checksum manifest")
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != match[1]:
        raise ValueError("Downloaded APK digest mismatch")
    verified = verify_apk(apk, records)
    packaged = json.loads((folder / "packaging.json").read_text(encoding="utf-8"))
    if packaged != verified:
        raise ValueError("Packaging report disagrees with independent verification")
    subprocess.run([apksigner, "verify", str(apk)], check=True, timeout=120)
    badging = subprocess.check_output([aapt, "dump", "badging", str(apk)],
                                      text=True, timeout=60)
    if not badging.startswith("package: name='" + PACKAGE + "' ") or (
        "application-debuggable" not in badging.splitlines()
    ):
        raise ValueError("Expected isolated debuggable package")
    return {"scope": "download integrity and packaging only; not device acceptance",
            "apk_sha256": digest, "package": PACKAGE, "candidate_sha256": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, required=True)
    parser.add_argument("--comparison", type=Path, required=True)
    parser.add_argument("--aapt", required=True)
    parser.add_argument("--apksigner", required=True)
    args = parser.parse_args()
    print(json.dumps(audit(args.folder, args.comparison, args.aapt, args.apksigner),
                     indent=2))


if __name__ == "__main__":
    main()
