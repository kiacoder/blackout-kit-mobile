#!/usr/bin/env python3
"""Stage locally built WG/AWG artifacts for opt-in DEBUG builds only.
Usage: python3 tool/stage_native_tunnels.py AWG_BUILD WG_BUILD
No downloads. No replacement of existing staging. Not release approval.
"""
from pathlib import Path
import hashlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    out = ROOT / '.cache/native-tunnel-jni'
    if out.exists():
        raise SystemExit('Staging already exists; preserve/review it before choosing a new build.')
    artifacts = []
    for engine, arg in zip(('awg', 'wireguard'), sys.argv[1:]):
        source = Path(arg).resolve()
        provenance = (source / 'PROVENANCE.txt').read_text()
        if f'Engine: {engine}\n' not in provenance:
            raise SystemExit('Engine provenance mismatch')
        pins = {'awg': 'ff15093bf3856fea0947923474870b86efb682f0',
                'wireguard': 'e7b3a3c118836e112620b1302a8ba1873ad4daac'}
        if f'Source revision: {pins[engine]}\n' not in provenance:
            raise SystemExit('Source provenance mismatch')
        required = ['tool/prepare_android_go_bridge.py',
                    'tool/patches/tun-consume-fd-on-error.patch']
        if engine == 'awg':
            required.append('tool/patches/awg-refresh-padding-after-tun-read.patch')
        recorded = {line.split()[0] for line in provenance.splitlines() if line.split()}
        for relative in required:
            if hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() not in recorded:
                raise SystemExit('Artifact predates required ownership/bridge patch; rebuild')
        hashes = {}
        for line in (source / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split(maxsplit=1)
            hashes[name.lstrip('*')] = digest
        for abi in ('arm64-v8a', 'armeabi-v7a'):
            name = f'{abi}/libblackout-{engine}.so'
            binary = source / name
            if hashlib.sha256(binary.read_bytes()).hexdigest() != hashes.get(name):
                raise SystemExit('Artifact hash mismatch')
            prefix = ('Java_org_amnezia_awg_GoBackend_awg' if engine == 'awg'
                      else 'Java_com_wireguard_android_backend_GoBackend_wg')
            required_symbols = [prefix + method for method in
                                ('TurnOn', 'TurnOff', 'GetSocketV4', 'GetSocketV6',
                                 'GetConfig', 'Version', 'IsClosed')]
            command = [sys.executable, str(ROOT / 'tool/check_android_artifact.py'),
                       '--binary', str(binary), '--abi', abi, '--min-sdk', '24']
            for symbol in required_symbols:
                command += ['--require-symbol', symbol]
            subprocess.run(command, check=True)
            artifacts.append((binary, out / name))
    # Nothing is staged until all four gates pass. Inputs stay untouched.
    for source, target in artifacts:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    print('Staged four development libraries. Enable via -PenableNativeTunnels=true for debug only.')
    print('NOT an APK build, license clearance, Android execution or connection test.')

if __name__ == '__main__':
    main()
