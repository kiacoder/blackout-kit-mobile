#!/usr/bin/env python3
"""Prepare dependency changes in a disposable checkout, not the shipping app."""
import argparse
from pathlib import Path


def candidate_manifest(source):
    for old, new in (
        ("file_picker: ^8.0.0", "file_picker: 8.1.7"),
        ("package_info_plus: 5.0.1", "package_info_plus: 8.3.1"),
    ):
        if source.count(new) == 1 and source.count(old) == 0:
            continue
        if source.count(old) != 1 or new in source:
            raise ValueError("Unexpected dependency constraint: " + old)
        source = source.replace(old, new)
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    path = args.manifest
    path.write_text(candidate_manifest(path.read_text(encoding="utf-8")), encoding="utf-8")


if __name__ == "__main__":
    main()
