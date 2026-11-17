import contextlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from config_factory import (ProfileError, parse_profiles, write_package, main, MAX_BYTES)

KEY = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
WG = f'''[Interface]
PrivateKey = {KEY}
Address = 10.0.0.2/32, fd00::2/128
DNS = 1.1.1.1
[Peer]
PublicKey = {KEY}
Endpoint = [2001:db8::1]:51820
AllowedIPs = 0.0.0.0/0, ::/0
'''
LINK = 'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#Test'


class FactoryTests(unittest.TestCase):
    def test_app_full_document_batch_roundtrip(self):
        mihomo = 'proxies: [{name: direct, type: direct}]\nrules: [MATCH,direct]\n'
        profiles = parse_profiles(json.dumps([LINK, WG, mihomo]))
        self.assertEqual(['xray', 'wireguard', 'mihomo'], [p.engine for p in profiles])
        self.assertEqual(WG, profiles[1].content)
        self.assertEqual(mihomo, profiles[2].content)

    def test_mihomo_json_document_preserved(self):
        raw = json.dumps({'proxies': [{'name': 'direct', 'type': 'direct'}],
                          'proxy-groups': [], 'rules': ['MATCH,direct']})
        profile = parse_profiles(raw)[0]
        self.assertEqual('mihomo', profile.engine)
        self.assertEqual(raw + '\n', profile.content)
        with self.assertRaises(ProfileError):
            parse_profiles(raw, 'xray')

    def test_mixed_engine_json_rejected(self):
        with self.assertRaises(ProfileError):
            parse_profiles('{"proxies": [{"type": "direct"}], "outbounds": [{"type": "direct"}]}')

    def test_batch_nesting_bounded(self):
        raw = LINK
        for _ in range(10):
            raw = json.dumps([raw])
        with self.assertRaises(ProfileError):
            parse_profiles(raw)

    def test_standard_wireguard(self):
        p = parse_profiles(WG)[0]
        self.assertEqual('wireguard', p.engine)
        self.assertEqual(WG, p.content)

    def test_new_awg_fields_never_downgrade(self):
        for key in ['Jc', 'S1', 'S2', 'S3', 'S4', 'H1', 'I1', 'I2', 'I3', 'I4', 'I5']:
            with self.subTest(key=key):
                raw = WG.replace('[Peer]', f'{key} = 42\n[Peer]')
                p = parse_profiles(raw)[0]
                self.assertEqual('amneziawg', p.engine)
                self.assertEqual(raw, p.content)
                with self.assertRaises(ProfileError):
                    parse_profiles(raw, 'wireguard')

    def test_multi_peer_lossless(self):
        raw = WG + f'[Peer]\nPublicKey = {KEY}\nAllowedIPs = 192.0.2.0/24\n'
        self.assertEqual(raw, parse_profiles(raw)[0].content)

    def test_awg_header_ranges_preserved(self):
        raw = WG.replace('[Peer]', 'H1 = 100-200\nI1 = <b 0x1234>\n[Peer]')
        self.assertEqual(raw, parse_profiles(raw)[0].content)

    def test_invalid_wg(self):
        for raw in [WG.replace(KEY, 'bad'), WG.replace('10.0.0.2/32', 'invalid'),
                    WG + '[Interface]\n', WG.replace('51820', '99999'),
                    WG.replace('DNS =', 'PrivateKey =')]:
            with self.subTest(raw_length=len(raw)), self.assertRaises(ProfileError):
                parse_profiles(raw)

    def test_hysteria1_rejected(self):
        with self.assertRaises(ProfileError):
            parse_profiles('hysteria://secret@example.com:443')

    def test_new_protocols_companion_only(self):
        for scheme in ['hy2', 'hysteria2', 'tuic', 'anytls', 'shadowtls']:
            self.assertFalse(parse_profiles(f'{scheme}://secret@example.com:443')[0].v2rayn)

    def test_json_engine_detection(self):
        for key, engine in [('type', 'sing-box'), ('protocol', 'xray')]:
            raw = json.dumps({'outbounds': [{key: 'direct'}]})
            self.assertEqual(engine, parse_profiles(raw)[0].engine)

    def test_json_ambiguous_and_duplicate_rejected(self):
        for raw in ['{"outbounds":[],"outbounds":[]}',
                    '{"outbounds":[{"type":"direct","protocol":"freedom"}]}',
                    '{"outbounds":[{"type":"direct"}],"x":NaN}']:
            with self.assertRaises(ProfileError):
                parse_profiles(raw)

    def test_json_formatting_duplicates(self):
        a = parse_profiles('{"outbounds":[{"type":"direct"}]}')[0]
        b = parse_profiles('{ "outbounds": [ { "type": "direct" } ] }')[0]
        self.assertEqual(a.identity, b.identity)

    def test_yaml_lossless_rules_and_groups(self):
        raw = 'proxies: [{name: direct, type: direct}]\nproxy-groups: []\nrules: [MATCH,direct]\n'
        self.assertEqual(raw, parse_profiles(raw)[0].content)

    def test_yaml_unsafe_rejected(self):
        for raw in ['proxies: !!python/object/apply:os.system [echo forbidden]',
                    'proxies: &a [*a]', 'proxies: []\nproxies: [x]',
                    'proxies: [' * 100 + ']' * 100]:
            with self.assertRaises(ProfileError):
                parse_profiles(raw, 'mihomo')

    def test_openvpn_preserves_hooks_without_executing(self):
        raw = 'client\ndev tun\nremote example.com 1194\nup /never/execute\n'
        self.assertEqual(raw, parse_profiles(raw)[0].content)

    def test_base64_subscription(self):
        import base64
        encoded = base64.b64encode((LINK + '\n' + LINK).encode()).decode()
        self.assertEqual(2, len(parse_profiles(encoded)))

    def test_json_uri_array(self):
        self.assertEqual(2, len(parse_profiles(json.dumps([LINK, LINK]))))

    def test_invalid_uri_ports(self):
        for port in ['0', '99999', 'wrong']:
            with self.assertRaises(ProfileError):
                parse_profiles(LINK.replace(':443', ':' + port))

    def test_input_limit(self):
        with self.assertRaises(ProfileError):
            parse_profiles('x' * (MAX_BYTES + 1))

    def test_empty_inputs(self):
        for raw in ['', '\x00', '[]']:
            with self.assertRaises(ProfileError):
                parse_profiles(raw)

    def test_manifest_dedup_separation_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'package'
            profiles = parse_profiles(LINK + '\n' + LINK) + parse_profiles(WG)
            manifest = write_package(profiles, dest, 'frankfurt-1')
            self.assertEqual(1, manifest['duplicatesRemoved'])
            self.assertFalse(manifest['connectionTested'])
            self.assertFalse(manifest['serverAssignmentVerified'])
            self.assertEqual(LINK + '\n', (dest / 'v2rayn.txt').read_text())
            self.assertNotIn(KEY, (dest / 'manifest.json').read_text())
            self.assertEqual(0o700, stat.S_IMODE(dest.stat().st_mode))
            for file in dest.iterdir():
                self.assertEqual(0o600, stat.S_IMODE(file.stat().st_mode))
            with self.assertRaises(FileExistsError):
                write_package(profiles, dest)

    def test_symlink_destination_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'link'
            dest.symlink_to(Path(temp), target_is_directory=True)
            with self.assertRaises(FileExistsError):
                write_package(parse_profiles(LINK), dest)

    def test_cli_does_not_echo_secret_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'secret-filename'
            source.write_text('vless://SUPERSECRET@example.com:99999')
            output = io.StringIO()
            with contextlib.redirect_stderr(output):
                result = main([str(source), '--output', str(Path(temp) / 'out')])
            self.assertEqual(2, result)
            self.assertNotIn('SUPERSECRET', output.getvalue())
            self.assertNotIn('secret-filename', output.getvalue())
            self.assertFalse((Path(temp) / 'out').exists())

    def test_explicit_hint_cannot_silently_change_engine(self):
        with self.assertRaises(ProfileError):
            parse_profiles(LINK, 'mihomo')

    def test_profile_count_limit(self):
        with self.assertRaises(ProfileError):
            parse_profiles('\n'.join([LINK] * 1001))

    def test_failed_write_removes_only_new_package(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / 'new'
            untouched = Path(temp) / 'existing'
            untouched.write_text('keep')
            real_open = os.open
            def fail_create(path, flags, *args, **kwargs):
                if flags & os.O_CREAT:
                    raise OSError('disk full')
                return real_open(path, flags, *args, **kwargs)
            with patch('config_factory.os.open', side_effect=fail_create):
                with self.assertRaises(OSError):
                    write_package(parse_profiles(LINK), dest)
            self.assertFalse(dest.exists())
            self.assertEqual('keep', untouched.read_text())

    def test_cli_roundtrip(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'input.txt'
            source.write_text(LINK)
            with contextlib.redirect_stdout(io.StringIO()):
                result = main([str(source), '--output', str(Path(temp) / 'out')])
            self.assertEqual(0, result)
            saved = json.loads((Path(temp) / 'out' / 'manifest.json').read_text())
            self.assertEqual('structural-only', saved['validation'])


if __name__ == '__main__':
    unittest.main()
