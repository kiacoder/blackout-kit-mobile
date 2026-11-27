#!/usr/bin/env python3
"""Fail-closed ELF metadata/export gate, NOT Android execution proof.
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


def dynamic_symbols(data):
    """Return defined dynamic-symbol names directly from the ELF binary."""
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[5] != 1:
        raise ValueError('Expected a little-endian ELF artifact')
    bits = data[4]
    if bits == 2:
        shoff = struct.unpack_from('<Q', data, 40)[0]
        shentsize, shnum = struct.unpack_from('<HH', data, 58)
        expected_sh = 64
        symbol_size = 24
    elif bits == 1:
        shoff = struct.unpack_from('<I', data, 32)[0]
        shentsize, shnum = struct.unpack_from('<HH', data, 46)
        expected_sh = 40
        symbol_size = 16
    else:
        raise ValueError('Unsupported ELF class')
    if shnum == 0 or shentsize < expected_sh or shnum > 16384:
        raise ValueError('Missing or invalid ELF section headers')
    if shoff + shentsize * shnum > len(data):
        raise ValueError('Truncated ELF section headers')

    sections = []
    for index in range(shnum):
        entry = shoff + index * shentsize
        section_type = struct.unpack_from('<I', data, entry + 4)[0]
        if bits == 2:
            offset = struct.unpack_from('<Q', data, entry + 24)[0]
            length = struct.unpack_from('<Q', data, entry + 32)[0]
            link = struct.unpack_from('<I', data, entry + 40)[0]
            entsize = struct.unpack_from('<Q', data, entry + 56)[0]
        else:
            offset = struct.unpack_from('<I', data, entry + 16)[0]
            length = struct.unpack_from('<I', data, entry + 20)[0]
            link = struct.unpack_from('<I', data, entry + 24)[0]
            entsize = struct.unpack_from('<I', data, entry + 36)[0]
        if section_type != 8 and offset + length > len(data):  # SHT_NOBITS has no file payload.
            raise ValueError('Truncated ELF section')
        sections.append((section_type, offset, length, link, entsize))

    names = set()
    dynsyms = [section for section in sections if section[0] == 11]  # SHT_DYNSYM
    if not dynsyms:
        raise ValueError('Missing ELF dynamic symbol table')
    for _, offset, length, link, entsize in dynsyms:
        if link >= len(sections):
            raise ValueError('Invalid ELF dynamic string-table link')
        str_type, str_offset, str_length, _, _ = sections[link]
        if str_type != 3:  # SHT_STRTAB
            raise ValueError('Invalid ELF dynamic string table')
        if entsize < symbol_size or length % entsize != 0:
            raise ValueError('Invalid ELF dynamic symbol table')
        for pos in range(offset, offset + length, entsize):
            name_offset = struct.unpack_from('<I', data, pos)[0]
            shndx_offset = 6 if bits == 2 else 14
            shndx = struct.unpack_from('<H', data, pos + shndx_offset)[0]
            if shndx == 0 or name_offset >= str_length:
                continue
            start = str_offset + name_offset
            end = data.find(b'\0', start, str_offset + str_length)
            if end < 0:
                raise ValueError('Unterminated ELF dynamic symbol name')
            if end > start:
                names.add(data[start:end].decode('utf-8', errors='strict'))
    return names


def validate(data, abi, min_sdk, required_symbols=()):
    result = inspect_elf(data)
    expected = {'arm64-v8a': (183, 64), 'armeabi-v7a': (40, 32), 'x86_64': (62, 64)}[abi]
    if (result['machine'], result['bits']) != expected or result['type'] != 3:
        raise ValueError('Wrong ABI or non-DYN artifact')
    if result['androidApi'] > min_sdk:
        raise ValueError(f"Artifact targets API {result['androidApi']}, above app minSdk {min_sdk}")
    if required_symbols:
        symbols = dynamic_symbols(data)
        missing = sorted(set(required_symbols) - symbols)
        if missing:
            raise ValueError('Missing required dynamic symbols: ' + ', '.join(missing))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--abi', required=True, choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
    parser.add_argument('--min-sdk', type=int, default=24)
    parser.add_argument('--require-symbol', action='append', default=[])
    args = parser.parse_args()
    try:
        result = validate(args.binary.read_bytes(), args.abi, args.min_sdk,
                          required_symbols=args.require_symbol)
    except (ValueError, OSError, struct.error) as error:
        # Never print file contents or OS error paths.
        message = str(error) if isinstance(error, ValueError) else 'Cannot inspect artifact'
        raise SystemExit('REJECTED: ' + message)
    print(f"PASS metadata gate: API {result['androidApi']}, {result['bits']}-bit ELF DYN")
    print('Device execution, dependent symbols, page-size compatibility and VPN forwarding NOT tested.')
