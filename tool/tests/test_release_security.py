import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from tool.release_security import inventory, signer_digest, verify_apks

class ReleaseSecurityTests(unittest.TestCase):
    def apk(self, folder, abi='arm64-v8a', extra=None):
        path = folder / 'blackout-kit-test-arm64-v8a.apk'
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('AndroidManifest.xml', b'manifest')
            z.writestr('classes.dex', b'dex')
            for lib in ('libflutter.so','libapp.so','libgojni.so','libblackout_core.so'):
                z.writestr(f'lib/{abi}/{lib}', b'lib')
            if extra: z.writestr(extra, b'unexpected')
        return path

    def test_valid_inventory(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(len(inventory(self.apk(Path(d)), {'arm64-v8a'})), 4)

    def test_experimental_library_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):
                inventory(self.apk(Path(d), extra='lib/arm64-v8a/libblackout-tunnels.so'), {'arm64-v8a'})

    def test_wrong_abi_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):
                inventory(self.apk(Path(d)), {'armeabi-v7a'})

    def test_signer_count(self):
        line = 'Signer #1 certificate SHA-256 digest: ' + 'a'*64
        self.assertEqual(signer_digest(line), 'a'*64)
        with self.assertRaises(ValueError):
            signer_digest(line + '\n' + line.replace('#1','#2'))

    def test_tag_requires_existing_certificate(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'ANDROID_RELEASE_CERT_SHA256'):
                verify_apks(Path(d), 'apksigner', True, '')

if __name__ == '__main__':
    unittest.main()
