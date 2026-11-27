import tempfile
import unittest
from pathlib import Path
import zipfile

from tool.apk_compare import compare


class ApkCompareTest(unittest.TestCase):
    def test_payload_match_is_not_byte_match(self):
        with tempfile.TemporaryDirectory() as directory:
            a, b = (Path(directory) / name for name in ("a.apk", "b.apk"))
            for path, year in ((a, 2020), (b, 2021)):
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr(zipfile.ZipInfo("classes.dex", (year, 1, 1, 0, 0, 0)), b"fixture")
            result = compare(a, b)
            self.assertFalse(result["exact_match"])
            self.assertTrue(result["payload_match"])
            self.assertTrue(compare(a, a)["exact_match"])

    def test_modified_entry_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            a, b = (Path(directory) / name for name in ("a.apk", "b.apk"))
            for path, payload in ((a, b"first"), (b, b"second")):
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("classes.dex", payload)
            result = compare(a, b)
            self.assertFalse(result["payload_match"])
            self.assertEqual(result["changed_entries"], ["classes.dex"])
