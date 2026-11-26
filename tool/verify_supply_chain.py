#!/usr/bin/env python3
'''Verify checked-in binary inventory and immutable workflow references.'''
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path

SUFFIXES = {'.aar', '.jar', '.so', '.a', '.dll', '.dylib', '.exe', '.apk', '.ipa'}
PIN = re.compile(r'^[^@\s]+@[a-f0-9]{40}$')
USES = re.compile(r'^\s*(?:-\s*)?uses:\s*([^#\r\n]+)', re.M)

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def verify(root, tracked, inventory):
    if inventory.get('schema') != 1:
        raise ValueError('Unsupported inventory schema')
    actual = {name for name in tracked if Path(name).suffix.lower() in SUFFIXES}
    records = inventory['artifacts']
    names = [r['path'] for r in records]
    if len(names) != len(set(names)) or set(names) != actual:
        raise ValueError('Tracked binary inventory is missing, duplicated or stale')
    for record in records:
        path = root / record['path']
        if path.is_symlink() or not path.is_file() or root.resolve() not in path.resolve().parents:
            raise ValueError('Unsafe or missing binary: ' + record['path'])
        if path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            raise ValueError('Binary digest mismatch: ' + record['path'])
        if 'native_members' in record:
            with zipfile.ZipFile(path) as archive:
                members = [n for n in archive.namelist() if n.startswith('jni/') and n.endswith('.so')]
                if len(members) != len(set(members)):
                    raise ValueError('Duplicate native archive members')
                hashes = {}
                for name in members:
                    with archive.open(name) as stream:
                        hashes[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
                if hashes != record['native_members']:
                    raise ValueError('Native archive member mismatch')
    for path in sorted((root / '.github/workflows').glob('*')):
        if path.suffix not in {'.yml', '.yaml'}:
            continue
        for value in USES.findall(path.read_text(encoding='utf-8')):
            value = value.strip().strip('"').strip("'")
            if value.startswith('./'):
                continue
            if not PIN.fullmatch(value):
                raise ValueError(f'Mutable action reference in {path.name}: {value}')
    return len(records)

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
    inventory = json.loads((root / 'tool/native_artifact_inventory.json').read_text(encoding='utf-8'))
    print(f'Verified {verify(root, tracked, inventory)} tracked binaries and all workflow action references.')
