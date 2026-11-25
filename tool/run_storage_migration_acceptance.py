#!/usr/bin/env python3
"""Verify and exercise only the synthetic storage fixture on a disposable emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

PACKAGE = "com.blackoutkit.storagefixture"
MODES = {"legacy": "1", "candidate": "2", "backup": "2"}


def run(*args, timeout=60):
    return subprocess.run(args, check=True, text=True, capture_output=True,
                          timeout=timeout).stdout.strip()


def verify_fixtures(folder, aapt, signer):
    hashes = {}
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([a-f0-9]{64}) [ *](legacy|candidate|backup)\.apk", line)
        if not match or match[2] in hashes:
            raise ValueError("Invalid fixture checksum manifest")
        hashes[match[2]] = match[1]
    if set(hashes) != set(MODES):
        raise ValueError("Missing fixture checksums")
    certs = set()
    for mode, version in MODES.items():
        apk = folder / (mode + ".apk")
        with apk.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != hashes[mode]:
                raise ValueError("Fixture hash mismatch")
        badging = run(aapt, "dump", "badging", str(apk))
        if not re.search(r"^package: name='" + re.escape(PACKAGE)
                         + r"' versionCode='" + version + r"'", badging, re.M):
            raise ValueError("Refusing non-fixture package or version")
        report = run(signer, "verify", "--print-certs", str(apk))
        fingerprints = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})$", report, re.M)
        if len(fingerprints) != 1:
            raise ValueError("Expected one verified fixture signer")
        certs.add(fingerprints[0].lower())
    if len(certs) != 1:
        raise ValueError("Fixture signatures differ")
    return hashes


def accept(folder, adb, serial):
    def device(*args, timeout=60):
        return run(adb, "-s", serial, *args, timeout=timeout)

    if (not re.fullmatch(r"emulator-\d+", serial)
            or device("get-state") != "device"
            or device("shell", "getprop", "ro.kernel.qemu") != "1"):
        raise ValueError("Only an explicitly selected authorized emulator is allowed")
    api = int(device("shell", "getprop", "ro.build.version.sdk"))
    if api < 24:
        raise ValueError("Android API 24+ required")
    if f"package:{PACKAGE}" in device("shell", "pm", "list", "packages", PACKAGE).splitlines():
        raise ValueError("Fixture already installed; use a fresh disposable emulator")

    def launch(marker):
        device("shell", "am", "force-stop", PACKAGE)
        result = device("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
        if "Status: ok" not in result:
            raise ValueError("Fixture failed to launch")
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            try:
                pid = device("shell", "pidof", PACKAGE)
            except subprocess.CalledProcessError:
                pid = ""
            if re.fullmatch(r"\d+", pid):
                log = device("logcat", "-d", "--pid=" + pid, "-v", "brief", "-s", "flutter:I")
                if "STORAGE_MIGRATION_FAIL" in log:
                    raise ValueError("Fixture reported migration failure")
                if marker in log:
                    return
            time.sleep(2)
        raise ValueError("Missing expected fixture marker: " + marker)

    results = {}
    for mode in ("candidate", "backup"):
        installed = False
        try:
            if device("install", "-t", str(folder / "legacy.apk"), timeout=120).splitlines()[-1:] != ["Success"]:
                raise ValueError("Legacy fixture install failed")
            installed = True
            launch("STORAGE_LEGACY_PASS")
            device("shell", "am", "force-stop", PACKAGE)
            if device("install", "-r", "-t", str(folder / (mode + ".apk")), timeout=120).splitlines()[-1:] != ["Success"]:
                raise ValueError("Candidate update failed")
            launch("STORAGE_MIGRATION_PASS")
            launch("STORAGE_MIGRATION_PASS")
            results[mode] = "upgrade-and-restart-passed"
        except (ValueError, subprocess.SubprocessError) as error:
            results[mode] = "failed: " + str(error)
        finally:
            if installed and device("uninstall", PACKAGE) != "Success":
                raise ValueError("Disposable fixture cleanup failed")
    return {"api": api, "abi": device("shell", "getprop", "ro.product.cpu.abi"),
            "results": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, required=True)
    parser.add_argument("--aapt", required=True)
    parser.add_argument("--apksigner", required=True)
    parser.add_argument("--adb")
    parser.add_argument("--serial")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    hashes = verify_fixtures(args.folder, args.aapt, args.apksigner)
    report = {"sha256": hashes, "scope": "synthetic fixture only; not production acceptance"}
    if args.adb or args.serial:
        if not args.adb or not args.serial:
            raise ValueError("Provide both adb and emulator serial")
        report.update(accept(args.folder, args.adb, args.serial))
    else:
        report["results"] = "artifact-verification-only"
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    if isinstance(report["results"], dict) and any(
            value != "upgrade-and-restart-passed" for value in report["results"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
