import hashlib
import tempfile
import unittest
from pathlib import Path
from tool.verify_supply_chain import verify

class SupplyChainTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.binary = self.root / 'fixture.so'
        self.binary.write_bytes(b'synthetic')
        self.inventory = {'schema': 1, 'artifacts': [{
            'path': 'fixture.so', 'bytes': 9,
            'sha256': hashlib.sha256(b'synthetic').hexdigest()}]}
        self.workflows = self.root / '.github/workflows'
        self.workflows.mkdir(parents=True)
        self.workflow = self.workflows / 'test.yml'
        self.workflow.write_text('      - uses: example/action@' + 'a'*40 + '\n')

    def check(self, tracked=None):
        return verify(self.root, tracked or ['fixture.so'], self.inventory)

    def test_exact_inventory_passes(self):
        self.assertEqual(self.check(), 1)

    def test_changed_binary_rejected(self):
        self.binary.write_bytes(b'tampered!')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.check()

    def test_unknown_binary_rejected(self):
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.check(['fixture.so', 'new.jar'])

    def test_duplicate_entry_rejected(self):
        self.inventory['artifacts'].append(self.inventory['artifacts'][0])
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.check()

    def test_mutable_action_rejected(self):
        self.workflow.write_text('      - uses: example/action@v1\n        with:\n          value: abc\n')
        with self.assertRaisesRegex(ValueError, 'Mutable action'):
            self.check()

    def test_local_action_allowed(self):
        self.workflow.write_text('      - uses: ./.github/actions/local\n')
        self.assertEqual(self.check(), 1)
