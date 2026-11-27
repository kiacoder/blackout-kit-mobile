import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "run_gradle_ci.sh"
PLUGIN_FAILURE = """Plugin [id: 'org.jetbrains.kotlin.android', version: '2.4.21', apply: false] was not found
could not resolve plugin artifact 'org.jetbrains.kotlin.android:org.jetbrains.kotlin.android.gradle.plugin:2.4.21'
"""


@unittest.skipUnless(os.name == "posix" and shutil.which("bash"), "POSIX CI shell required")
class GradleCiTests(unittest.TestCase):
    def run_fixture(self, first, second=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "gradlew").write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> calls\n"
                "if [ -f attempt ]; then exit " + str(second) + "; fi\n"
                "touch attempt\n"
                "cat first-output\n"
                "exit " + str(first[0]) + "\n",
                encoding="utf-8",
            )
            (root / "first-output").write_text(first[1], encoding="utf-8")
            sleeper = root / "sleep"
            sleeper.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            sleeper.chmod(0o700)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(
                ["bash", str(SCRIPT), ":app:testDebugUnitTest"],
                cwd=root, env=env, capture_output=True, text=True, timeout=10,
            )
            return result.returncode, (root / "calls").read_text().splitlines()

    def test_known_resolution_failure_retries_exact_task(self):
        code, calls = self.run_fixture((1, PLUGIN_FAILURE))
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["--no-daemon :app:testDebugUnitTest"] * 2)

    def test_second_failure_remains_failure(self):
        code, calls = self.run_fixture((1, PLUGIN_FAILURE), second=7)
        self.assertEqual(code, 7)
        self.assertEqual(len(calls), 2)

    def test_unit_failure_does_not_retry(self):
        code, calls = self.run_fixture((3, "Tests failed"))
        self.assertEqual(code, 3)
        self.assertEqual(len(calls), 1)

    def test_success_does_not_retry(self):
        code, calls = self.run_fixture((0, "BUILD SUCCESSFUL"))
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 1)
