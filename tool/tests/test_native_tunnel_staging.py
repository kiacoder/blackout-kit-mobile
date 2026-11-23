import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / 'stage_native_tunnels.py'
SPEC = importlib.util.spec_from_file_location('stage_native_tunnels_under_test', SCRIPT)
stage = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(stage)


class NativeTunnelStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'combined-build'
        self.source.mkdir(parents=True)
        for relative in stage.REQUIRED_FILES:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('fixture:' + relative).encode())

        provenance = [
            'Artifact: combined WG/AWG Android JNI library',
            *stage.PINS,
        ]
        for relative in stage.REQUIRED_FILES:
            digest = hashlib.sha256((self.root / relative).read_bytes()).hexdigest()
            provenance.append(f'{digest}  {relative}')
        (self.source / 'PROVENANCE.txt').write_text('\n'.join(provenance) + '\n')

        sums = []
        for abi in ('arm64-v8a', 'armeabi-v7a'):
            binary = self.source / abi / 'libblackout-tunnels.so'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(('binary:' + abi).encode())
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            sums.append(f'{digest}  {abi}/libblackout-tunnels.so')
        (self.source / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')

    def tearDown(self):
        self.temp.cleanup()

    def run_main(self, subprocess_side_effect=None):
        with mock.patch.object(stage, 'ROOT', self.root), \
             mock.patch.object(sys, 'argv', ['stage_native_tunnels.py', str(self.source)]), \
             mock.patch.object(stage.subprocess, 'run',
                               side_effect=subprocess_side_effect) as run:
            stage.main()
            return run

    def test_valid_combined_build_checks_both_abis_and_all_exports_then_stages(self):
        run = self.run_main()
        self.assertEqual(2, run.call_count)
        required = {
            prefix + method
            for prefix in stage.PREFIXES
            for method in stage.METHODS
        }
        self.assertEqual(14, len(required))
        for call in run.call_args_list:
            command = call.args[0]
            seen = {
                command[i + 1]
                for i, value in enumerate(command[:-1])
                if value == '--require-symbol'
            }
            self.assertEqual(required, seen)
        for abi in ('arm64-v8a', 'armeabi-v7a'):
            staged = self.root / '.cache/native-tunnel-jni' / abi / 'libblackout-tunnels.so'
            self.assertTrue(staged.is_file())

    def test_second_abi_failure_leaves_no_partial_staging(self):
        failure = subprocess.CalledProcessError(1, ['checker'])
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_main([None, failure])
        self.assertFalse((self.root / '.cache/native-tunnel-jni').exists())

    def test_hash_mismatch_is_rejected_before_checker_or_staging(self):
        binary = self.source / 'arm64-v8a' / 'libblackout-tunnels.so'
        binary.write_bytes(b'tampered')
        with mock.patch.object(stage, 'ROOT', self.root), \
             mock.patch.object(sys, 'argv', ['stage_native_tunnels.py', str(self.source)]), \
             mock.patch.object(stage.subprocess, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'Artifact hash mismatch'):
                stage.main()
            run.assert_not_called()
        self.assertFalse((self.root / '.cache/native-tunnel-jni').exists())

    def test_missing_required_source_digest_is_rejected(self):
        provenance = (self.source / 'PROVENANCE.txt').read_text().splitlines()
        digest = hashlib.sha256(
            (self.root / stage.REQUIRED_FILES[0]).read_bytes()
        ).hexdigest()
        (self.source / 'PROVENANCE.txt').write_text(
            '\n'.join(line for line in provenance if digest not in line) + '\n'
        )
        with mock.patch.object(stage, 'ROOT', self.root), \
             mock.patch.object(sys, 'argv', ['stage_native_tunnels.py', str(self.source)]), \
             mock.patch.object(stage.subprocess, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'predates required combined source/patch'):
                stage.main()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
