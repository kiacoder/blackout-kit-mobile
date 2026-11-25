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
PACKAGE_INFO_CANDIDATE = "8.3.1"
GRADLE_SHA = "544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d"


def candidate_manifest(source):
    replacements = {
        "flutter_secure_storage: ^9.0.0": "flutter_secure_storage: 10.3.4",
        "package_info_plus: 5.0.1": "package_info_plus: " + PACKAGE_INFO_CANDIDATE,
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError("Unexpected app dependency constraint: " + old)
        source = source.replace(old, new)
    return source


def fixture_toolchain(folder):
    settings = folder / "android/settings.gradle"
    source = settings.read_text(encoding="utf-8")
    for old, new in (
        ('id "com.android.application" version "7.3.0"', 'id "com.android.application" version "8.5.2"'),
        ('id "org.jetbrains.kotlin.android" version "1.7.10"', 'id "org.jetbrains.kotlin.android" version "2.0.21"'),
    ):
        if source.count(old) != 1 and source.count(new) != 1:
            raise ValueError("Unexpected generated Gradle plugin version")
        source = source.replace(old, new)
    settings.write_text(source, encoding="utf-8")
    wrapper = folder / "android/gradle/wrapper/gradle-wrapper.properties"
    source = wrapper.read_text(encoding="utf-8")
    lines = [line for line in source.splitlines()
             if not line.startswith(("distributionUrl=", "distributionSha256Sum="))]
    lines.extend([r"distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-bin.zip",
                  "distributionSha256Sum=" + GRADLE_SHA])
    wrapper.write_text("\n".join(lines) + "\n", encoding="utf-8")


def app_toolchain(root):
    """Apply the separately tested toolchain only in a disposable CI checkout."""
    edits = {
        "android/settings.gradle": [
            ('version "7.4.2"', 'version "8.5.2"'),
            ('version "1.9.25"', 'version "2.0.21"'),
        ],
        "android/app/build.gradle": [
            ('    namespace = "com.blackoutkit.vpn"',
             '    namespace = "com.blackoutkit.vpn"\n    buildFeatures {\n        buildConfig = true\n    }'),
        ],
        "android/gradle/wrapper/gradle-wrapper.properties": [
            ("gradle-7.6.6-all.zip", "gradle-8.7-bin.zip"),
            ("6ed4d467349e2d3f555a578829c4aeadd67d73e2ec5d213c2a62f8f2829d9fa9", GRADLE_SHA),
        ],
    }
    changed = {}
    for name, replacements in edits.items():
        path = root / name
        source = path.read_text(encoding="utf-8")
        for old, new in replacements:
            if source.count(old) != 1 or new in source:
                raise ValueError("Unexpected application toolchain: " + name)
            source = source.replace(old, new)
        changed[path] = source
    for path, source in changed.items():
        path.write_text(source, encoding="utf-8")


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
    source = source.replace('id "kotlin-android"', 'id "org.jetbrains.kotlin.android"')
    source = source.replace("JavaVersion.VERSION_1_8", "JavaVersion.VERSION_17")
    gradle.write_text(source, encoding="utf-8")
    fixture_toolchain(folder)
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
