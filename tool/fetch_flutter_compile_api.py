#!/usr/bin/env python3
"""Recover official Flutter 3.24.0 Java declarations for a narrow Kotlin check.

NOT a Flutter SDK, embedding binary, Java compilation, or complete app build.
Requires authenticated gh; reads public source only and verifies Git blob IDs.
"""
import base64
import hashlib
import json
from pathlib import Path
import subprocess

REVISION = 'b8800d88be4866db1b15f8b954ab2573bba9960f'
FILES = {
    'embedding/engine/plugins/FlutterPlugin.java': '055126f0ff3c761cd7ab3309225ce7349e2944fb',
    'embedding/engine/plugins/activity/ActivityAware.java': '10fb0983167585120facd314f1fd3bd6c21c2472',
    'embedding/engine/plugins/activity/ActivityPluginBinding.java': '8c5f84b453c8ae71a318abd8446b13c34b7d4886',
    'plugin/common/MethodCall.java': '7181a548e713abb1bc2eab92434545c02b0cd79f',
    'plugin/common/MethodChannel.java': '3191aa4e3ad66cc7affde3c1a69ad75507816de0',
    'plugin/common/PluginRegistry.java': '4859617d93b29dc581757aa49ff48f11c710e3bf',
    'plugin/common/BinaryMessenger.java': 'eef8e047a0afe3112d6646a88d2c1f82424555ba',
}


def main():
    root = Path(__file__).resolve().parents[1] / '.cache/flutter-api-source'
    for name, expected in FILES.items():
        path = root / name
        if path.exists():
            content = path.read_bytes()
        else:
            url = f'repos/flutter/engine/contents/shell/platform/android/io/flutter/{name}?ref={REVISION}'
            response = subprocess.run(['gh', 'api', url], check=True, capture_output=True, timeout=30)
            content = base64.b64decode(json.loads(response.stdout)['content'])
        actual = hashlib.sha1(f'blob {len(content)}\0'.encode() + content).hexdigest()
        if actual != expected:
            raise SystemExit(f'Official source mismatch: {name}; refusing overwrite')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print('Verified seven official Flutter Java declarations. NOT an installed Flutter SDK.')


if __name__ == '__main__':
    main()
