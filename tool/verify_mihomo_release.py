#!/usr/bin/env python3
"""Verify an unpacked candidate against an exact official compressed release.

No candidate is executed. gzip metadata is restored from the verified upstream
archive; matching the complete archive digest authenticates the payload too.
Requires GNU gzip with the upstream default compression (level 6).
"""
import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile

RELEASES = {
    'linux-amd64': {
        'name': 'mihomo-linux-amd64', 'mtime': 1794379830,
        'archive_sha256': '223fab877e5795ce780ba39902e5f0b1113c1256ae244a7160f1165e017e9ccc',
        'binary_sha256': '0a68807c7c93963bb66d07717fe0f3ac3945b422b525f8a1e19438d278d7ae11',
        'asset_id': 734505033,
    },
    'android-arm64': {
        'name': 'mihomo-android-arm64-v8', 'mtime': 1794380113,
        'archive_sha256': '48a71fc6a68e2909587176e0ab7185d8f2fac298fa96ccdacf30ea86ab2359b5',
        'asset_id': 734505069,
    },
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=RELEASES, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    args = parser.parse_args()
    release = RELEASES[args.platform]
    data = args.binary.read_bytes()
    with tempfile.TemporaryDirectory(prefix='mihomo-verify-') as directory:
        path = Path(directory) / release['name']
        path.write_bytes(data)
        archive = bytearray(subprocess.run(['gzip', '-6', '-c', str(path)],
                                          check=True, capture_output=True, timeout=30).stdout)
    if archive[:4] != b'\x1f\x8b\x08\x08':
        raise SystemExit('Unexpected gzip header; verification aborted')
    archive[4:8] = struct.pack('<I', release['mtime'])
    if hashlib.sha256(archive).hexdigest() != release['archive_sha256']:
        raise SystemExit('Official archive digest MISMATCH; do not execute/package')
    print('PASS exact official v1.19.34 archive SHA-256:', release['archive_sha256'])
    print('Binary SHA-256:', hashlib.sha256(data).hexdigest())
    print('GitHub release asset ID:', release['asset_id'])
    print('Integrity only: NOT Android compatibility, licensing clearance, or VPN testing.')


if __name__ == '__main__':
    main()
