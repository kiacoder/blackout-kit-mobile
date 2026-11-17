#!/usr/bin/env python3
"""Fail-closed ELF metadata gate, NOT Android execution/ABI compatibility proof.
ET_DYN covers shared libraries and PIE executables; this does not distinguish them."""
import argparse
from pathlib import Path
import struct


def inspect_elf(data):
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[5] != 1:
        raise ValueError('Expected a little-endian ELF artifact')
    bits = data[4]
    kind, machine = struct.unpack_from('<HH', data, 16)
    if bits == 2:
        phoff = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        expected_size = 56
    elif bits == 1:
        phoff = struct.unpack_from('<I', data, 28)[0]
        size, count = struct.unpack_from('<HH', data, 42)
        expected_size = 32
    else:
        raise ValueError('Unsupported ELF class')
    if size < expected_size or count > 4096 or phoff + count * size > len(data):
        raise ValueError('Invalid ELF program headers')
    apis = set()
    for index in range(count):
        entry = phoff + index * size
        if struct.unpack_from('<I', data, entry)[0] != 4:  # PT_NOTE
            continue
        if bits == 2:
            offset = struct.unpack_from('<Q', data, entry + 8)[0]
            length = struct.unpack_from('<Q', data, entry + 32)[0]
        else:
            offset = struct.unpack_from('<I', data, entry + 4)[0]
            length = struct.unpack_from('<I', data, entry + 16)[0]
        end = offset + length
        if end > len(data):
            raise ValueError('Truncated ELF note segment')
        while offset < end:
            if offset + 12 > end:
                raise ValueError('Truncated ELF note')
            namesz, descsz, note_type = struct.unpack_from('<III', data, offset)
            offset += 12
            desc = offset + ((namesz + 3) & ~3)
            following = desc + ((descsz + 3) & ~3)
            if following > end:
                raise ValueError('Invalid ELF note bounds')
            if data[offset:offset + namesz].rstrip(b'\0') == b'Android' and note_type == 1:
                if descsz < 4:
                    raise ValueError('Missing Android API note')
                apis.add(struct.unpack_from('<I', data, desc)[0])
            offset = following
    if len(apis) != 1:
        raise ValueError('Missing or conflicting Android API metadata')
    return {'machine': machine, 'type': kind, 'bits': 64 if bits == 2 else 32,
            'androidApi': apis.pop()}


def validate(data, abi, min_sdk):
    result = inspect_elf(data)
    expected = {'arm64-v8a': (183, 64), 'armeabi-v7a': (40, 32)}[abi]
    if (result['machine'], result['bits']) != expected or result['type'] != 3:
        raise ValueError('Wrong ABI or non-DYN artifact')
    if result['androidApi'] > min_sdk:
        raise ValueError(f"Artifact targets API {result['androidApi']}, above app minSdk {min_sdk}")
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--abi', required=True, choices=['arm64-v8a', 'armeabi-v7a'])
    parser.add_argument('--min-sdk', type=int, default=24)
    args = parser.parse_args()
    try:
        result = validate(args.binary.read_bytes(), args.abi, args.min_sdk)
    except (ValueError, OSError, struct.error) as error:
        # Never print file contents or OS error paths.
        message = str(error) if isinstance(error, ValueError) else 'Cannot inspect artifact'
        raise SystemExit('REJECTED: ' + message)
    print(f"PASS metadata gate: API {result['androidApi']}, {result['bits']}-bit ELF DYN")
    print('Device execution, dependent symbols, page-size compatibility and VPN forwarding NOT tested.')
