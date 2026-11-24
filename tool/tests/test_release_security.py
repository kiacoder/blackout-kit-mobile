import tempfile
import unittest
import zipfile
from pathlib import Path
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
        report = 'Verifies\nNumber of signers: 1\n' + line
        self.assertEqual(signer_digest(report), 'a'*64)
        for invalid in (line, report + '\n' + line.replace('#1','#2'),
                        report.replace('signers: 1','signers: 2'),
                        report.replace('certificate SHA-256','public key SHA-256')):
            with self.assertRaises(ValueError):
                signer_digest(invalid)

    def test_numbered_leaf_certificate(self):
        report = ('Verifies\nNumber of signers: 1\n'
                  'Signer #1 certificate #1 SHA-256 digest: ' + 'AB'*32 + '\n'
                  'Signer #1 public key SHA-256 digest: ' + 'cd'*32 + '\n')
        self.assertEqual(signer_digest(report), 'ab'*32)

    def test_tag_requires_existing_certificate(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'ANDROID_RELEASE_CERT_SHA256'):
                verify_apks(Path(d), 'apksigner', True, '')

if __name__ == '__main__':
    unittest.main()
