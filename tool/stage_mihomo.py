#!/usr/bin/env python3
"""Review locally built Mihomo candidates and stage both ABIs for private debug use."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

try:
    from .check_android_artifact import validate
except ImportError:
    from check_android_artifact import validate

ROOT = Path(__file__).resolve().parents[1]
PIN = "0455d0d28c4526937380505153e65a843d8612e8"
VERSION = "v1.19.34"
GO = "go1.26.11"
ABIS = {"arm64-v8a": "arm64", "armeabi-v7a": "arm"}


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def check_build_info(info, arch):
    lines = set(info.splitlines())
    required = {
        "\tpath\tgithub.com/metacubex/mihomo",
        "\tbuild\tGOOS=android",
        "\tbuild\tGOARCH=" + arch,
        "\tbuild\tCGO_ENABLED=1",
        "\tbuild\t-trimpath=true",
        "\tbuild\tvcs.revision=" + PIN,
        "\tbuild\tvcs.modified=false",
    }
    if not lines or not info.splitlines()[0].endswith(": " + GO) or not required <= lines:
        raise ValueError("Unexpected Mihomo build metadata")
    if not any(line.split("\t")[:4] == ["", "mod", "github.com/metacubex/mihomo", VERSION]
               for line in lines):
        raise ValueError("Unexpected Mihomo module version")


def inspect_candidates(build, source):
    if run("git", "-C", str(source), "rev-parse", "HEAD") != PIN:
        raise ValueError("Wrong Mihomo source revision")
    if run("git", "-C", str(source), "status", "--porcelain"):
        raise ValueError("Mihomo source checkout is not clean")
    license_path = source / "LICENSE"
    if "GNU GENERAL PUBLIC LICENSE" not in license_path.read_text(encoding="utf-8"):
        raise ValueError("Mihomo license missing")
    records = []
    for abi, arch in ABIS.items():
        path = build / abi / "libmihomo.so"
        info = run("go", "version", "-m", str(path))
        check_build_info(info, arch)
        elf = validate(path.read_bytes(), abi, 24)
        records.append({"abi": abi, "sha256": sha(path), "size": path.stat().st_size,
                        "elf": elf, "go": GO, "sourceCommit": PIN, "version": VERSION})
    return records


def stage(build, source, root=ROOT):
    cache = root / ".cache"
    output = cache / "mihomo-jni"
    if output.exists():
        raise ValueError("Existing staging must be reviewed; refusing to overwrite")
    records = inspect_candidates(build, source)
    cache.mkdir(exist_ok=True)
    # Build all files in a new temporary directory and publish only after both
    # artifacts have passed the exact ABI, source and checksum gates.
    with tempfile.TemporaryDirectory(prefix="mihomo-stage-", dir=cache) as temp:
        pending = Path(temp) / "staged"
        for record in records:
            abi = record["abi"]
            dest = pending / abi / "libmihomo.so"
            dest.parent.mkdir(parents=True)
            shutil.copy2(build / abi / "libmihomo.so", dest)
            if sha(dest) != record["sha256"]:
                raise ValueError("Staged artifact differs from reviewed candidate")
        shutil.copy2(source / "LICENSE", pending / "LICENSE-mihomo")
        (pending / "PROVENANCE.json").write_text(json.dumps({
            "scope": "private debug candidate, not Android traffic or license distribution approval",
            "source": "https://github.com/MetaCubeX/mihomo/tree/" + PIN,
            "artifacts": records,
            "licenseSha256": sha(pending / "LICENSE-mihomo"),
        }, indent=2) + "\n", encoding="utf-8")
        pending.rename(output)
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    try:
        records = stage(args.build.resolve(), args.source.resolve())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, "Mihomo staging refused: " + str(error) + "\n")
    print(json.dumps(records, indent=2))
    print("Private debug only: -PenableMihomo=true. No runtime/device or release approval.")


if __name__ == "__main__":
    main()
