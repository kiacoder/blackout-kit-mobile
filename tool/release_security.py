#!/usr/bin/env python3
'''Verify exact distribution APKs and produce machine-readable evidence.'''
import argparse
import hashlib
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path

ABIS = {'arm64-v8a', 'armeabi-v7a'}
EXPERIMENTAL = {'libblackout-tunnels.so', 'libblackout-wireguard.so',
                'libblackout-awg.so', 'libprocess_guard.so', 'libprocess_guard_fixture.so'}
HEX = re.compile(r'[a-f0-9]{64}')

def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def inventory(path, expected_abis):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        if 'AndroidManifest.xml' not in names or 'classes.dex' not in names:
            raise ValueError('Missing Android manifest or DEX')
        libs = {}
        for info in z.infolist():
            name = info.filename
            if not name.startswith('lib/') or not name.endswith('.so'):
                continue
            parts = name.split('/')
            if len(parts) != 3 or parts[2] in EXPERIMENTAL:
                raise ValueError('Unexpected or experimental native library')
            with z.open(info) as f:
                libs[name] = hashlib.file_digest(f, 'sha256').hexdigest()
        actual = {name.split('/')[1] for name in libs}
        if actual != expected_abis:
            raise ValueError(f'Wrong ABI set: {actual}')
        for abi in expected_abis:
            for name in ('libflutter.so', 'libapp.so', 'libgojni.so', 'libblackout_core.so'):
                if f'lib/{abi}/{name}' not in libs:
                    raise ValueError(f'Missing required library: {abi}/{name}')
        return libs

def signer_digest(output):
    # The pinned Android build-tools reports one signer and one leaf
    # certificate. Also support numbered leaf certificate output.
    counts = re.findall(r'^Number of signers:[ \t]*(\d+)[ \t]*$', output, re.M)
    fingerprints = re.findall(
        r'^Signer #1 certificate(?: #1)? SHA-256 digest:[ \t]*([0-9a-fA-F]{64})[ \t]*$',
        output, re.M)
    all_digests = re.findall(r'^Signer #\d+ certificate(?: #\d+)? SHA-256 digest:', output, re.M)
    if counts != ['1'] or len(fingerprints) != 1 or len(all_digests) != 1:
        raise ValueError('Expected exactly one verified APK signer')
    return fingerprints[0].lower()

def package_identity(output):
    lines = [line for line in output.splitlines() if line.startswith('package:')]
    if len(lines) != 1:
        raise ValueError('Expected one APK package identity')
    match = re.match(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']*)'", lines[0])
    if not match or match[1] != 'com.blackoutkit.vpn':
        raise ValueError('Unexpected APK application identity')
    if 'application-debuggable' in output.splitlines():
        raise ValueError('Debuggable APK cannot be distributed as a release build')
    return {'package': match[1], 'version_code': match[2], 'version_name': match[3]}


def verify_keystore_certificate(path, expected, keytool='keytool'):
    """Check public certificate before signing; never print keystore contents."""
    if not HEX.fullmatch(expected):
        raise ValueError('Set ANDROID_RELEASE_CERT_SHA256 to the existing published signing certificate')
    alias = os.getenv('ANDROID_KEY_ALIAS')
    if not alias or not os.getenv('ANDROID_KEYSTORE_PASSWORD'):
        raise ValueError('Missing signing alias or keystore password')
    result = subprocess.run(
        [keytool, '-exportcert', '-keystore', str(path), '-alias', alias,
         '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD'],
        capture_output=True, timeout=60, check=False)
    if result.returncode != 0 or not result.stdout:
        raise ValueError('Could not read signing certificate')
    if hashlib.sha256(result.stdout).hexdigest() != expected:
        raise ValueError('Keystore certificate differs from pinned publisher certificate')


def verify_apks(folder, signer, tagged, expected, aapt=None):
    if tagged and not HEX.fullmatch(expected):
        raise ValueError('Set ANDROID_RELEASE_CERT_SHA256 to the existing published signing certificate')
    if not aapt:
        raise ValueError('Provide aapt for APK application identity verification')
    apks = sorted(folder.glob('*.apk'))
    if len(apks) != 3:
        raise ValueError('Expected exactly three APKs')
    records = []
    seen = set()
    for apk in apks:
        matches = [abi for abi in ('universal', *sorted(ABIS)) if apk.name.endswith(f'-{abi}.apk')]
        if len(matches) != 1 or matches[0] in seen:
            raise ValueError('Unexpected or duplicate APK variant')
        abi = matches[0]
        seen.add(abi)
        verified = subprocess.run([signer, 'verify', '--verbose', '--print-certs', str(apk)],
                                  check=True, text=True, capture_output=True, timeout=120,
                                  env={**os.environ, 'LC_ALL': 'C', 'LANG': 'C'})
        try:
            cert = signer_digest(verified.stdout)
        except ValueError:
            print('Unexpected apksigner report headers:',
                  [line.split(':', 1)[0] for line in verified.stdout.splitlines()
                   if line.startswith(('Signer ', 'Number of signers', 'Verified using'))])
            raise
        if tagged and cert != expected:
            raise ValueError('Release certificate differs from pinned publisher certificate')
        badging = subprocess.check_output([aapt, 'dump', 'badging', str(apk)],
                                          text=True, timeout=60)
        identity = package_identity(badging)
        records.append({'name': apk.name, 'bytes': apk.stat().st_size, 'sha256': digest(apk),
                        'signer_sha256': cert, 'identity': identity,
                        'native_libraries': inventory(apk, ABIS if abi == 'universal' else {abi})})
    if len({x['identity']['version_name'] for x in records}) != 1:
        raise ValueError('APK variants use different version names')
    if len({x['signer_sha256'] for x in records}) != 1:
        raise ValueError('APK variants use different signing certificates')
    (folder / 'APK_INVENTORY.json').write_text(json.dumps({
        'commit': os.getenv('GITHUB_SHA', ''), 'ref': os.getenv('GITHUB_REF', ''),
        'signing': 'release-certificate-pinned' if tagged else 'test-only',
        'apks': records}, indent=2) + '\n', encoding='utf-8')

def mobsf_findings(appsec):
    """Retain review identifiers without copying scanner-extracted secret values."""
    counts = {}
    findings = []
    for level in ('high', 'warning', 'info', 'secure', 'hotspot'):
        entries = appsec[level]
        if not isinstance(entries, list):
            raise ValueError('Malformed MobSF severity results')
        counts[level] = len(entries)
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError('Malformed MobSF finding')
            title, section = entry.get('title'), entry.get('section')
            description = entry.get('description')
            if (not isinstance(title, str) or not title.strip() or len(title) > 4096
                    or not isinstance(section, str) or not section.strip()
                    or len(section) > 128 or not isinstance(description, str)):
                raise ValueError('Malformed MobSF finding fields')
            # Full descriptions can include strings that look like credentials.
            # Hash the evidence rather than copying these into the compact report.
            fingerprint = hashlib.sha256(
                json.dumps([level, section, title, description],
                           ensure_ascii=False, separators=(',', ':')).encode('utf-8')
            ).hexdigest()
            # The rule identity is stable across changes in the affected file list.
            rule = hashlib.sha256(
                json.dumps([section, title], ensure_ascii=False,
                           separators=(',', ':')).encode('utf-8')
            ).hexdigest()
            findings.append({'severity': level, 'section': section, 'title': title,
                             'rule_sha256': rule, 'evidence_sha256': fingerprint})
    return counts, findings


def scanner_summary(folder, records):
    expected = {record['name']: record['sha256'] for record in records}
    if len(expected) != 3 or len(records) != 3:
        raise ValueError('Expected three unique APK inventory records')
    clam = (folder / 'CLAMAV_REPORT.txt').read_text(encoding='utf-8')
    for label, count in (('Scanned files', 3), ('Infected files', 0)):
        matches = re.findall(r'^' + label + r': ([0-9]+)[ \t]*$', clam, re.M)
        if matches != [str(count)]:
            raise ValueError('Unexpected ClamAV scan coverage or detections: ' + label)
    if re.search(r'^(?:Total errors|Errors): [1-9][0-9]*', clam, re.M):
        raise ValueError('ClamAV reported scan errors')
    vt = json.loads((folder / 'VIRUSTOTAL_REPORT.json').read_text(encoding='utf-8'))
    allowed = {'unknown-file', 'not-configured', 'lookup-error', 'report-found-review-required'}
    if (len(vt) != len(expected)
            or {record['file']: record['sha256'] for record in vt} != expected
            or any(record['status'] not in allowed for record in vt)):
        raise ValueError('VirusTotal report does not cover exact APK hashes')
    status = json.loads((folder / 'MOBSF_STATUS.json').read_text(encoding='utf-8'))
    mobsf = {'status': status['status']}
    report_path = folder / 'MOBSF_REPORT.json'
    if status['status'] == 'completed-review-required':
        report = json.loads(report_path.read_text(encoding='utf-8'))
        universal = [sha for name, sha in expected.items() if name.endswith('-universal.apk')]
        if len(universal) != 1 or report['sha256'] != universal[0]:
            raise ValueError('MobSF report does not match universal APK')
        appsec = report['appsec']
        counts, findings = mobsf_findings(appsec)
        score = appsec['security_score']
        if type(score) is not int or not 0 <= score <= 100:
            raise ValueError('Invalid MobSF security score')
        mobsf.update(scope='universal APK static analysis only',
                     score=score, counts=counts, findings=findings)
    elif status['status'] != 'not-configured' or report_path.exists():
        raise ValueError('Unexpected MobSF status or stale report')
    return {'clamav': {'scanned_files': 3, 'infected_files': 0},
            'virustotal': [{'file': r['file'], 'status': r['status']} for r in vt],
            'mobsf': mobsf,
            'review_required': True}


def make_report(folder):
    data = json.loads((folder / 'APK_INVENTORY.json').read_text(encoding='utf-8'))
    for record in data['apks']:
        if digest(folder / record['name']) != record['sha256']:
            raise ValueError('APK changed after verification')
    scanners = scanner_summary(folder, data['apks'])
    evidence = ('SBOM.spdx.json', 'CLAMAV_VERSION.txt', 'CLAMAV_REPORT.txt', 'MOBSF_STATUS.json', 'VIRUSTOTAL_REPORT.json')
    if (folder / 'MOBSF_REPORT.json').is_file():
        evidence += ('MOBSF_REPORT.json',)
    hashes = {name: digest(folder / name) for name in evidence}
    report = {'commit': data['commit'], 'ref': data['ref'], 'signing': data['signing'],
              'apk_inventory_sha256': digest(folder / 'APK_INVENTORY.json'),
              'evidence_sha256': hashes,
              'scanner_results': scanners,
              'malware_scan': 'ClamAV completed without detected malware or scanner errors',
              'limitations': ['Not a malware-free guarantee', 'SBOM is repository scan, not exhaustive binary dependency inventory',
                              'MobSF and VirusTotal require separate review', 'Device acceptance remains separate']}
    (folder / 'SECURITY_REPORT.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    (folder / 'SECURITY_REPORT.md').write_text(
        '# Release security evidence\n\n'
        f"Commit: {data['commit']}\n\nSigning: {data['signing']}\n\n"
        'APK signatures, ABI inventory and checksums verified. ClamAV scan completed without detections or errors. '
        'Repository SPDX SBOM and per-APK native library SHA-256 inventory attached. '
        f"MobSF: {scanners['mobsf']['status']}. VirusTotal: "
        + ', '.join(r['status'] for r in scanners['virustotal']) + '. '
        'This is not a malware-free guarantee. Review MobSF, VirusTotal and device results separately before publication.\n',
        encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--keystore', type=Path)
    parser.add_argument('--apk-dir', type=Path)
    parser.add_argument('--apksigner')
    parser.add_argument('--aapt')
    parser.add_argument('--report-dir', type=Path)
    args = parser.parse_args()
    if args.keystore:
        verify_keystore_certificate(args.keystore, os.getenv('EXPECTED_CERT_SHA256', '').lower().strip())
        print('Signing certificate matches the pinned publisher identity.')
    elif args.apk_dir and args.apksigner:
        verify_apks(args.apk_dir, args.apksigner, os.getenv('GITHUB_REF', '').startswith('refs/tags/v'),
                    os.getenv('EXPECTED_CERT_SHA256', '').lower().strip(), args.aapt)
    elif args.report_dir:
        make_report(args.report_dir)
    else:
        parser.error('Provide --keystore, --apk-dir and --apksigner, or --report-dir')

if __name__ == '__main__':
    main()
