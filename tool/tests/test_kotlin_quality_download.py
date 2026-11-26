import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from tool import check_kotlin_quality as quality


class KotlinQualityDownloadTests(unittest.TestCase):
    def test_rate_limit_recovers_and_honors_retry_after(self):
        limited = urllib.error.HTTPError("https://example.invalid", 429, "limited",
                                          {"Retry-After": "45"}, io.BytesIO())
        self.addCleanup(limited.close)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "tool.part"
            with patch.object(quality.urllib.request, "urlopen",
                              side_effect=[limited, io.BytesIO(b"fixture")]), \
                    patch.object(quality.time, "sleep") as sleep:
                quality.download("https://example.invalid", target)
            self.assertEqual(target.read_bytes(), b"fixture")
            sleep.assert_called_once_with(45)

    def test_permanent_error_not_retried(self):
        missing = urllib.error.HTTPError("https://example.invalid", 404, "missing", {}, io.BytesIO())
        self.addCleanup(missing.close)
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(quality.urllib.request, "urlopen", side_effect=missing) as request, \
                    patch.object(quality.time, "sleep") as sleep:
                with self.assertRaises(urllib.error.HTTPError):
                    quality.download("https://example.invalid", Path(directory) / "tool.part")
            self.assertEqual(request.call_count, 1)
            sleep.assert_not_called()

    def test_retry_budget_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(quality.urllib.request, "urlopen",
                              side_effect=urllib.error.URLError("offline")) as request, \
                    patch.object(quality.time, "sleep") as sleep:
                with self.assertRaises(urllib.error.URLError):
                    quality.download("https://example.invalid", Path(directory) / "tool.part")
            self.assertEqual(request.call_count, quality.DOWNLOAD_ATTEMPTS)
            self.assertEqual([call.args[0] for call in sleep.call_args_list], [5, 10, 20, 40, 60])
        self.assertEqual(quality.retry_delay(0, "999"), 60)
        self.assertEqual(quality.retry_delay(1, "invalid"), 10)

    def test_cached_checksum_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "ktlint.jar").write_bytes(b"unexpected")
            with patch.object(quality, "CACHE", cache), patch.object(quality, "download") as download:
                with self.assertRaisesRegex(RuntimeError, "cached checksum mismatch"):
                    quality.jar("ktlint")
                download.assert_not_called()
