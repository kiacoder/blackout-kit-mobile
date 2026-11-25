#!/usr/bin/env python3
"""Prepare disposable secure-storage fixtures; never modify production files."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSIONS = {"legacy": "9.2.4", "candidate": "10.3.4", "backup": "10.3.4"}
PACKAGE = "com.blackoutkit.storagefixture"
OLD_OPTIONS = "encryptedSharedPreferences: true,"


def candidate_source(source, backup=False):
    if source.count(OLD_OPTIONS) != 1 or "resetOnError: false," not in source:
        raise ValueError("Unexpected secure-store options; review migration")
    return source.replace(
        OLD_OPTIONS,
        "migrateOnAlgorithmChange: true,\n"
        f"                migrateWithBackup: {str(backup).lower()},",
    )


def prepare_fixture(folder, mode):
    if not (folder / "android/app/build.gradle").is_file():
        raise ValueError("Expected generated Flutter Android fixture")
    gradle = folder / "android/app/build.gradle"
    source = gradle.read_text(encoding="utf-8")
    if f'applicationId = "{PACKAGE}"' not in source:
        raise ValueError("Refusing to edit a non-fixture Android package")
    source = source.replace("flutter.minSdkVersion", "24")
    gradle.write_text(source, encoding="utf-8")
    version = VERSIONS[mode]
    manifest = (
        "name: storagefixture\npublish_to: none\n"
        "version: 1.0.0+" + ("1" if mode == "legacy" else "2") + "\n"
        "environment:\n  sdk: '>=3.5.0 <4.0.0'\n"
        "dependencies:\n  flutter:\n    sdk: flutter\n"
        f"  flutter_secure_storage: {version}\n"
        "  hive_flutter: 1.1.0\n  hive: 2.2.3\n"
    )
    (folder / "pubspec.yaml").write_text(manifest, encoding="utf-8")
    vault = (ROOT / "lib/services/secure_vault.dart").read_text(encoding="utf-8")
    if mode != "legacy":
        vault = candidate_source(vault, backup=mode == "backup")
    (folder / "lib/secure_vault.dart").write_text(vault, encoding="utf-8")
    shutil.copyfile(ROOT / "tool/fixtures/storage_migration/main.dart.snapshot", folder / "lib/main.dart")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", required=True, choices=VERSIONS)
    parser.add_argument("--folder", required=True, type=Path)
    parser.add_argument("--create", action="store_true")
    args = parser.parse_args()
    folder = args.folder.resolve()
    if ROOT.resolve() == folder or (ROOT / ".cache").resolve() not in folder.parents:
        raise ValueError("Fixture must be under the repository .cache directory")
    if args.create:
        if folder.exists():
            raise ValueError("Refusing to reuse a fixture directory")
        flutter = shutil.which("flutter")
        if not flutter:
            raise ValueError("Flutter executable not found")
        subprocess.run([flutter, "create", "--no-pub", "--platforms=android",
                        "--org", "com.blackoutkit", "--project-name", "storagefixture",
                        str(folder)], check=True, cwd=ROOT)
    prepare_fixture(folder, args.mode)


if __name__ == "__main__":
    main()
