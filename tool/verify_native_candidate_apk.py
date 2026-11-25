#!/usr/bin/env python3
"""Stage reviewed standalone candidates only in disposable CI; verify debug APK bytes."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import zipfile
import hashlib

if __package__:
    from .build_pinned_go_engines import ABIS, ENGINES
    from .compare_go_candidate_replicas import compare
else:
    from build_pinned_go_engines import ABIS, ENGINES
    from compare_go_candidate_replicas import compare

PREFIX = "android/app/src/main/jniLibs"
PACKAGE = "com.blackoutkit.vpn.nativetest"


def expected(replicas):
    return {
        f"lib/{abi}/lib{engine}.so": digest
        for engine in ENGINES
        for abi, digest in compare(replicas, engine)["sha256"].items()
    }


def stage(root, replicas):
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_OS") != "Linux":
        raise ValueError("Only a disposable Linux GitHub Actions checkout may be staged")
    if subprocess.check_output(["git", "-C", str(root), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise ValueError("Refusing a modified checkout")
    records = expected(replicas)
    for member in records:
        _, abi, name = member.split("/")
        if abi not in ABIS or not (root / PREFIX / abi / name).is_file():
            raise ValueError("Expected historical native slot missing")
    for member, digest in records.items():
        _, abi, name = member.split("/")
        engine = name[3:-3]
        source = replicas / f"native-go-{engine}-1" / abi / name
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("Candidate changed after comparison")
        destination = root / PREFIX / abi / name
        destination.write_bytes(data)
    return records


def verify_apk(apk, records):
    required = {f"lib/{abi}/lib{engine}.so" for abi in ABIS for engine in ENGINES}
    if set(records) != required:
        raise ValueError("Incomplete expected candidate inventory")
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate APK members")
        if any(name.startswith(("lib/x86/", "lib/x86_64/")) for name in names):
            raise ValueError("Unexpected native ABI in candidate APK")
        for name, digest in records.items():
            if name not in names:
                raise ValueError("Missing candidate APK member: " + name)
            with archive.open(name) as stream:
                actual = hashlib.file_digest(stream, "sha256").hexdigest()
            if actual != digest:
                raise ValueError("Packaged candidate bytes differ: " + name)
    return {"scope": "debug packaging only; not device acceptance",
            "package": PACKAGE, "sha256": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replicas", type=Path, required=True)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aapt")
    parser.add_argument("--stage", action="store_true")
    args = parser.parse_args()
    if args.stage:
        if args.apk or args.aapt:
            raise ValueError("Stage and verification are separate steps")
        stage(Path.cwd(), args.replicas)
        return
    if not args.apk or not args.aapt:
        raise ValueError("Provide APK and aapt")
    badging = subprocess.check_output([args.aapt, "dump", "badging", str(args.apk)], text=True)
    if not badging.startswith("package: name='" + PACKAGE + "' ") or "application-debuggable" not in badging.splitlines():
        raise ValueError("Expected isolated debuggable native test package")
    print(json.dumps(verify_apk(args.apk, expected(args.replicas)), indent=2))


if __name__ == "__main__":
    main()
