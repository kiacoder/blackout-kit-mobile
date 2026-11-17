import struct
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_android_artifact import inspect_elf, validate


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


class AndroidArtifactTests(unittest.TestCase):
    def test_api24_metadata_accepted(self):
        self.assertEqual(24, validate(fixture(), 'arm64-v8a', 24)['androidApi'])

    def test_api34_rejected_for_min24(self):
        with self.assertRaisesRegex(ValueError, 'above app minSdk'):
            validate(fixture(34), 'arm64-v8a', 24)

    def test_wrong_abi_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Wrong ABI'):
            validate(fixture(), 'armeabi-v7a', 24)

    def test_malformed_or_missing_metadata_rejected(self):
        for data in [b'', fixture()[:143], bytes(144), fixture()[:120]]:
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                inspect_elf(data)
