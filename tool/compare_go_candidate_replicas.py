#!/usr/bin/env python3
"""Verify candidate artifact hashes and compare independent build replicas."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

if __package__:
    from .build_pinned_go_engines import ABIS, ENGINES, PATCHED_GO_VERSION
    from .check_android_artifact import validate
else:
    from build_pinned_go_engines import ABIS, ENGINES, PATCHED_GO_VERSION
    from check_android_artifact import validate


def verify_replica(folder, engine):
    evidence = json.loads((folder / "PROVENANCE.json").read_text(encoding="utf-8"))
    if evidence["go"].split()[2] != PATCHED_GO_VERSION or evidence["pin"] != ENGINES[engine]:
        raise ValueError("Unexpected candidate engine or compiler")
    if evidence["osv"]["findings"] or not evidence["candidate_snapshot_sha256"]:
        raise ValueError("Candidate lacks required clean version audit or snapshot")
    records = {}
    for record in evidence["artifacts"]:
        abi = record["abi"]
        if abi not in ABIS or abi in records:
            raise ValueError("Unexpected or repeated ABI")
        binary = folder / abi / ("lib" + engine + ".so")
        data = binary.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != record["sha256"] or len(data) != record["bytes"]:
            raise ValueError("Candidate binary evidence mismatch")
        if validate(data, abi, 24) != record["elf"]:
            raise ValueError("Candidate ELF evidence mismatch")
        records[abi] = digest
    if set(records) != set(ABIS):
        raise ValueError("Missing ABI")
    return evidence, records


def compare(root, engine):
    first, a = verify_replica(root / f"native-go-{engine}-1", engine)
    second, b = verify_replica(root / f"native-go-{engine}-2", engine)
    for key in ("go", "ndk", "go_sha256", "clang_sha256", "candidate_snapshot_sha256"):
        if first[key] != second[key]:
            raise ValueError(f"Replica input mismatch: {key}")
    if a != b:
        raise ValueError(f"Independent {engine} binary hashes differ")
    return {"engine": engine, "sha256": a,
            "candidate_snapshot_sha256": first["candidate_snapshot_sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--engine", choices=ENGINES, action="append")
    args = parser.parse_args()
    try:
        results = [compare(args.root, engine) for engine in args.engine or ENGINES]
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        print(f"Replica verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"scope": "independent byte equality; not device acceptance",
                      "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
