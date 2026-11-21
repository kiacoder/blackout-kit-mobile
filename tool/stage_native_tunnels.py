#!/usr/bin/env python3
"""Stage the locally built combined WG/AWG artifact for opt-in DEBUG builds only.
Usage: python3 tool/stage_native_tunnels.py COMBINED_BUILD
No downloads. No replacement of existing staging. Not release approval.
"""
from pathlib import Path
import hashlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PINS = (
    'WireGuard source revision: e7b3a3c118836e112620b1302a8ba1873ad4daac',
    'AmneziaWG source revision: ff15093bf3856fea0947923474870b86efb682f0',
)
REQUIRED_FILES = (
    'tool/native_combined/api-combined.go',
    'tool/native_combined/jni-combined.c',
    'tool/patches/tun-consume-fd-on-error.patch',
    'tool/patches/awg-refresh-padding-after-tun-read.patch',
)
PREFIXES = (
    'Java_com_wireguard_android_backend_GoBackend_wg',
    'Java_org_amnezia_awg_GoBackend_awg',
)
METHODS = ('TurnOn', 'TurnOff', 'GetSocketV4', 'GetSocketV6',
           'GetConfig', 'Version', 'IsClosed')


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)

    source = Path(sys.argv[1]).resolve()
    out = ROOT / '.cache/native-tunnel-jni'
    if out.exists():
        raise SystemExit(
            'Staging already exists; preserve/review it before choosing a new build.'
        )

    provenance = (source / 'PROVENANCE.txt').read_text()
    if 'Artifact: combined WG/AWG Android JNI library' not in provenance:
        raise SystemExit('Combined artifact provenance mismatch')
    for pin in PINS:
        if pin not in provenance:
            raise SystemExit('Source provenance mismatch')

    recorded = {line.split()[0] for line in provenance.splitlines() if line.split()}
    for relative in REQUIRED_FILES:
        digest = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        if digest not in recorded:
            raise SystemExit(
                f'Artifact predates required combined source/patch: {relative}; rebuild'
            )

    hashes = {}
    for line in (source / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        hashes[name.lstrip('*')] = digest

    artifacts = []
    for abi in ('arm64-v8a', 'armeabi-v7a'):
        name = f'{abi}/libblackout-tunnels.so'
        binary = source / name
        if hashlib.sha256(binary.read_bytes()).hexdigest() != hashes.get(name):
            raise SystemExit('Artifact hash mismatch')

        command = [
            sys.executable,
            str(ROOT / 'tool/check_android_artifact.py'),
            '--binary', str(binary),
            '--abi', abi,
            '--min-sdk', '24',
        ]
        for prefix in PREFIXES:
            for method in METHODS:
                command += ['--require-symbol', prefix + method]
        subprocess.run(command, check=True)
        artifacts.append((binary, out / name))

    # Nothing is staged until both ABI gates pass. Inputs stay untouched.
    for binary, target in artifacts:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, target)

    print('Staged combined WG/AWG development library for ARM64 + ARMv7.')
    print('One Go runtime only. Enable via -PenableNativeTunnels=true for debug only.')
    print('NOT release approval; Android connection/traffic acceptance remains separate.')


if __name__ == '__main__':
    main()
