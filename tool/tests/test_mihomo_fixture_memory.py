import json
import os
import subprocess
import sys
import unittest
import tool.test_mihomo_core as mihomo_fixture

@unittest.skipUnless(sys.platform.startswith('linux') and hasattr(os, 'memfd_create'), 'Linux anonymous file fixture')
class MihomoFixtureMemoryTests(unittest.TestCase):
    def test_anonymous_config_readable_in_child(self):
        fixture = mihomo_fixture.CoreTests()
        fixture.config = {'secret': 'disposable-unit-test-value'}
        fd = fixture.config_fd()
        try:
            self.assertEqual(os.fstat(fd).st_mode & 0o777, 0o600)
            output = subprocess.run(
                [sys.executable, '-c', 'import pathlib,sys; sys.stdout.buffer.write(pathlib.Path(sys.argv[1]).read_bytes())',
                 f'/proc/self/fd/{fd}'],
                pass_fds=(fd,), check=True, capture_output=True, timeout=5)
            self.assertEqual(json.loads(output.stdout), fixture.config)
        finally:
            os.close(fd)
