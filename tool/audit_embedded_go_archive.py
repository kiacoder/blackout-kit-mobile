#!/usr/bin/env python3
"""Inspect embedded Go archive metadata without executing its native libraries."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

if __package__:
    from .audit_go_engine_locks import query_findings, request_batch
    from .build_pinned_go_engines import ABIS, dependency_records
else:
    from audit_go_engine_locks import query_findings, request_batch
    from build_pinned_go_engines import ABIS, dependency_records

GO_VERSION = re.compile(r"go(\d+\.\d+\.\d+)")
MODULE_VERSION = re.compile(r"v\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.\-]+)?")
CHECKSUM = re.compile(r"h1:[A-Za-z0-9+/]{43}=")


def inspect_info(info, abi):
    lines = info.splitlines()
    compiler = lines[0].rsplit(": ", 1)[-1]
    version = GO_VERSION.fullmatch(compiler)
    arch = ABIS[abi][0]
    if not version or not {
        "\tbuild\tGOOS=android", "\tbuild\tGOARCH=" + arch,
        "\tbuild\tCGO_ENABLED=1",
    } <= set(lines):
        raise ValueError("Unexpected Go compiler or target metadata")
    main = [line.split("\t")[2:] for line in lines if line.startswith("\tmod\t")]
    if len(main) != 1 or len(main[0]) not in (2, 3):
        raise ValueError("Unexpected main module metadata")
    deps = dependency_records(info)
    if main[0][0] in deps:
        raise ValueError("Duplicate main module")
    records = {main[0][0]: main[0][1:], **deps}
    known = {("stdlib", version[1])}
    unknown = []
    for name, record in records.items():
        if len(record) == 5 and record[1] == "=>":
            effective, mod_version, checksum = record[2:]
        elif len(record) == 2:
            effective, mod_version, checksum = name, *record
        else:
            effective, mod_version, checksum = "", "", ""
        if (effective and not effective.startswith((".", "/"))
                and MODULE_VERSION.fullmatch(mod_version) and CHECKSUM.fullmatch(checksum)):
            known.add((effective, mod_version))
        else:
            unknown.append({"abi": abi, "module": name, "metadata": record,
                            "reason": "unresolved source identity"})
    return compiler, deps, known, unknown


def audit_archive(archive, fetch=request_batch):
    data = archive.read_bytes()
    members, owners, unknown = {}, {}, []
    expected = {"jni/" + abi + "/libgojni.so" for abi in ABIS}
    with zipfile.ZipFile(archive) as package, tempfile.TemporaryDirectory() as directory:
        entries = [name for name in package.namelist()
                   if name.startswith("jni/") and name.endswith(".so")]
        if set(entries) != expected or len(entries) != len(expected):
            raise ValueError("Unexpected or duplicate native AAR entries")
        for abi in ABIS:
            blob = package.read("jni/" + abi + "/libgojni.so")
            path = Path(directory) / "libgojni.so"
            path.write_bytes(blob)
            info = subprocess.check_output(["go", "version", "-m", str(path)], text=True)
            compiler, deps, known, unresolved = inspect_info(info, abi)
            members[abi] = {"sha256": hashlib.sha256(blob).hexdigest(),
                            "go": compiler, "dependencies": deps}
            for key in known:
                owners.setdefault(key, []).append(abi)
            unknown.extend(unresolved)
    return {"schema": 1, "source": "https://api.osv.dev/v1/querybatch",
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "scope": "effective linked module versions and stdlib; unresolved sources excluded; not reachability",
            "aar_sha256": hashlib.sha256(data).hexdigest(),
            "members": members, "unknown": unknown,
            "unique_module_versions": len(owners),
            "findings": query_findings(owners, fetch)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    try:
        report = audit_archive(args.archive)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, IndexError, KeyError,
            subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Embedded audit incomplete: {error}", file=sys.stderr)
        return 2
    print(f"Queried {report['unique_module_versions']} versions; "
          f"{len(report['findings'])} matches; {len(report['unknown'])} unresolved ABI/source entries.")
    return 1 if args.strict and (report["findings"] or report["unknown"]) else 0


if __name__ == "__main__":
    sys.exit(main())
