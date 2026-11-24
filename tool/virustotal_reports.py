#!/usr/bin/env python3
'''Optional hash-only lookup. Never submits APKs or claims unknown files are safe.'''
import hashlib
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path

def main(folder):
    key = os.environ.get('VT_API_KEY', '')
    records = []
    for apk in sorted(folder.glob('*.apk')):
        with apk.open('rb') as f:
            sha = hashlib.file_digest(f, 'sha256').hexdigest()
        record = {'file': apk.name, 'sha256': sha,
                  'url': 'https://www.virustotal.com/gui/file/' + sha,
                  'status': 'not-configured'}
        if key:
            try:
                req = urllib.request.Request('https://www.virustotal.com/api/v3/files/' + sha,
                                             headers={'x-apikey': key})
                with urllib.request.urlopen(req, timeout=25) as r:
                    result = json.load(r)['data']
                if result['id'] != sha:
                    raise ValueError('Hash mismatch')
                attrs = result['attributes']
                record.update(status='report-found-review-required',
                              last_analysis_stats=attrs.get('last_analysis_stats'),
                              last_analysis_date=attrs.get('last_analysis_date'))
            except urllib.error.HTTPError as e:
                record['status'] = 'unknown-file' if e.code == 404 else 'lookup-error'
                record['http_status'] = e.code
            except (OSError, ValueError, KeyError):
                record['status'] = 'lookup-error'
        records.append(record)
    (folder / 'VIRUSTOTAL_REPORT.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    # Never interpret an unknown file or missing report as a clean scan.
    print('VirusTotal hash lookup:', ', '.join(r['status'] for r in records))
    if key and any(r['status'] == 'lookup-error' for r in records):
        print('VirusTotal returned a lookup error; manual review is required.', file=sys.stderr)

if __name__ == '__main__':
    main(Path(sys.argv[1]))
