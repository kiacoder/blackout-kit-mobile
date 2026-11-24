import hashlib
import io
import json
import os
import tempfile
import unittest
import unittest.mock
import urllib.error
from pathlib import Path
from tool import virustotal_reports


class VirusTotalReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.apk = self.folder / 'fixture.apk'
        self.apk.write_bytes(b'not a real APK')
        self.sha = hashlib.sha256(self.apk.read_bytes()).hexdigest()

    def report(self):
        virustotal_reports.main(self.folder)
        return json.loads((self.folder / 'VIRUSTOTAL_REPORT.json').read_text())[0]

    def test_missing_key_does_not_call_network(self):
        with unittest.mock.patch.dict(os.environ, {'VT_API_KEY': ''}), \
             unittest.mock.patch('urllib.request.urlopen') as request:
            self.assertEqual(self.report()['status'], 'not-configured')
            request.assert_not_called()

    def test_unknown_file_is_not_a_clean_scan(self):
        error = urllib.error.HTTPError('https://www.virustotal.com/', 404,
                                       'Not found', {}, None)
        with unittest.mock.patch.dict(os.environ, {'VT_API_KEY': 'fixture-key'}), \
             unittest.mock.patch('urllib.request.urlopen', side_effect=error):
            result = self.report()
        self.assertEqual(result['status'], 'unknown-file')
        self.assertNotIn('last_analysis_stats', result)

    def test_report_is_bound_to_exact_hash_and_never_uploads(self):
        data = {'data': {'id': self.sha, 'attributes': {
            'last_analysis_stats': {'malicious': 1, 'undetected': 5},
            'last_analysis_date': 1}}}
        with unittest.mock.patch.dict(os.environ, {'VT_API_KEY': 'fixture-key'}), \
             unittest.mock.patch('urllib.request.urlopen',
                                 return_value=io.BytesIO(json.dumps(data).encode())) as request:
            result = self.report()
        self.assertEqual(result['status'], 'report-found-review-required')
        self.assertEqual(result['last_analysis_stats']['malicious'], 1)
        self.assertEqual(request.call_args.args[0].get_method(), 'GET')
        self.assertTrue(request.call_args.args[0].full_url.endswith('/files/' + self.sha))

    def test_mismatched_hash_is_an_error(self):
        data = {'data': {'id': '0' * 64, 'attributes': {}}}
        with unittest.mock.patch.dict(os.environ, {'VT_API_KEY': 'fixture-key'}), \
             unittest.mock.patch('urllib.request.urlopen',
                                 return_value=io.BytesIO(json.dumps(data).encode())):
            self.assertEqual(self.report()['status'], 'lookup-error')
