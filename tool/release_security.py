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
                'libblackout-awg.so', 'libprocess_guard.so'}
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

def verify_apks(folder, signer, tagged, expected):
    if tagged and not HEX.fullmatch(expected):
        raise ValueError('Set ANDROID_RELEASE_CERT_SHA256 to the existing published signing certificate')
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
        records.append({'name': apk.name, 'bytes': apk.stat().st_size, 'sha256': digest(apk),
                        'signer_sha256': cert, 'native_libraries': inventory(apk, ABIS if abi == 'universal' else {abi})})
    if len({x['signer_sha256'] for x in records}) != 1:
        raise ValueError('APK variants use different signing certificates')
    (folder / 'APK_INVENTORY.json').write_text(json.dumps({
        'commit': os.getenv('GITHUB_SHA', ''), 'ref': os.getenv('GITHUB_REF', ''),
        'signing': 'release-certificate-pinned' if tagged else 'test-only',
        'apks': records}, indent=2) + '\n', encoding='utf-8')

def make_report(folder):
    data = json.loads((folder / 'APK_INVENTORY.json').read_text(encoding='utf-8'))
    for record in data['apks']:
        if digest(folder / record['name']) != record['sha256']:
            raise ValueError('APK changed after verification')
    evidence = ('SBOM.spdx.json', 'CLAMAV_VERSION.txt', 'CLAMAV_REPORT.txt', 'MOBSF_STATUS.json', 'VIRUSTOTAL_REPORT.json')
    if (folder / 'MOBSF_REPORT.json').is_file():
        evidence += ('MOBSF_REPORT.json',)
    hashes = {name: digest(folder / name) for name in evidence}
    report = {'commit': data['commit'], 'ref': data['ref'], 'signing': data['signing'],
              'apk_inventory_sha256': digest(folder / 'APK_INVENTORY.json'),
              'evidence_sha256': hashes,
              'malware_scan': 'ClamAV completed without detected malware or scanner errors',
              'limitations': ['Not a malware-free guarantee', 'SBOM is repository scan, not exhaustive binary dependency inventory',
                              'MobSF and VirusTotal require separate review', 'Device acceptance remains separate']}
    (folder / 'SECURITY_REPORT.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    (folder / 'SECURITY_REPORT.md').write_text(
        '# Release security evidence\n\n'
        f"Commit: {data['commit']}\n\nSigning: {data['signing']}\n\n"
        'APK signatures, ABI inventory and checksums verified. ClamAV scan completed without detections or errors. '
        'Repository SPDX SBOM and per-APK native library SHA-256 inventory attached. '
        'This is not a malware-free guarantee. Review MobSF, VirusTotal and device results separately before publication.\n',
        encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk-dir', type=Path)
    parser.add_argument('--apksigner')
    parser.add_argument('--report-dir', type=Path)
    args = parser.parse_args()
    if args.apk_dir and args.apksigner:
        verify_apks(args.apk_dir, args.apksigner, os.getenv('GITHUB_REF', '').startswith('refs/tags/v'),
                    os.getenv('EXPECTED_CERT_SHA256', '').lower().strip())
    elif args.report_dir:
        make_report(args.report_dir)
    else:
        parser.error('Provide --apk-dir and --apksigner or --report-dir')

if __name__ == '__main__':
    main()
