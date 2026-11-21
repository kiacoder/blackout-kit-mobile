import struct
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_android_artifact import dynamic_symbols, inspect_elf, validate


def fixture(api=24):
    data = bytearray(144)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<HH', data, 16, 3, 183)
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 4)
    struct.pack_into('<Q', data, 72, 120)
    struct.pack_into('<Q', data, 96, 24)
    struct.pack_into('<III', data, 120, 8, 4, 1)
    data[132:140] = b'Android\0'
    struct.pack_into('<I', data, 140, api)
    return data


def symbol_fixture(symbol='Java_com_wireguard_android_backend_GoBackend_wgVersion'):
    data = bytearray(560)
    data[:144] = fixture()
    struct.pack_into('<Q', data, 40, 160)  # section-header offset
    struct.pack_into('<HH', data, 58, 64, 3)

    encoded = b'\0' + symbol.encode() + b'\0'
    # Section 1: dynamic string table.
    struct.pack_into('<I', data, 160 + 64 + 4, 3)
    struct.pack_into('<Q', data, 160 + 64 + 24, 448)
    struct.pack_into('<Q', data, 160 + 64 + 32, len(encoded))
    data[448:448 + len(encoded)] = encoded

    # Section 2: SHT_DYNSYM with a null entry and one defined symbol.
    section = 160 + 128
    struct.pack_into('<I', data, section + 4, 11)
    struct.pack_into('<Q', data, section + 24, 400)
    struct.pack_into('<Q', data, section + 32, 48)
    struct.pack_into('<I', data, section + 40, 1)
    struct.pack_into('<Q', data, section + 56, 24)
    struct.pack_into('<I', data, 424, 1)  # st_name
    struct.pack_into('<H', data, 430, 1)  # st_shndx: defined
    return data


class AndroidArtifactTests(unittest.TestCase):
    def test_api24_metadata_accepted(self):
        self.assertEqual(24, validate(fixture(), 'arm64-v8a', 24)['androidApi'])

    def test_api34_rejected_for_min24(self):
        with self.assertRaisesRegex(ValueError, 'above app minSdk'):
            validate(fixture(34), 'arm64-v8a', 24)

    def test_wrong_abi_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Wrong ABI'):
            validate(fixture(), 'armeabi-v7a', 24)

    def test_dynamic_symbol_is_read_from_binary(self):
        symbol = 'Java_com_wireguard_android_backend_GoBackend_wgVersion'
        self.assertIn(symbol, dynamic_symbols(symbol_fixture(symbol)))
        validate(symbol_fixture(symbol), 'arm64-v8a', 24,
                 required_symbols=[symbol])

    def test_missing_required_dynamic_symbol_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing required dynamic symbols'):
            validate(symbol_fixture(), 'arm64-v8a', 24,
                     required_symbols=['Java_missing_symbol'])

    def test_malformed_or_missing_metadata_rejected(self):
        for data in [b'', fixture()[:143], bytes(144), fixture()[:120]]:
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                inspect_elf(data)
