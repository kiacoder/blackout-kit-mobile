#!/usr/bin/env python3
"""Compare independent APK builds without treating payload equality as reproducibility."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha256_file(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def entries(path):
    result = {}
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            if entry.filename in result:
                raise ValueError("Duplicate ZIP entry: " + entry.filename)
            with archive.open(entry) as stream:
                result[entry.filename] = hashlib.file_digest(stream, "sha256").hexdigest()
    return result


def compare(first, second):
    hashes = [sha256_file(first), sha256_file(second)]
    a, b = entries(first), entries(second)
    return {
        "exact_match": hashes[0] == hashes[1],
        "sha256": hashes,
        "only_first": sorted(a.keys() - b.keys()),
        "only_second": sorted(b.keys() - a.keys()),
        "changed_entries": sorted(k for k in a.keys() & b.keys() if a[k] != b[k]),
        "payload_match": a == b,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    args = parser.parse_args()
    result = compare(args.first, args.second)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["exact_match"] else 1)


if __name__ == "__main__":
    main()
