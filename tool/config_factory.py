#!/usr/bin/env python3
"""Offline, lossless profile packaging. Structural checks are NOT engine validation.

Never fetches subscriptions, executes profile directives, or contacts VPN servers.
Outputs contain secrets; use a private destination outside version control.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import sys
from dataclasses import dataclass
from urllib.parse import urlsplit

MAX_BYTES = 8 * 1024 * 1024
MAX_PROFILES = 1000
AWG_KEYS = {'jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4',
            'h1', 'h2', 'h3', 'h4', 'i1', 'i2', 'i3', 'i4', 'i5'}
URI_PROTOCOLS = {'vless', 'vmess', 'trojan', 'ss', 'hy2', 'hysteria2',
                 'tuic', 'anytls', 'shadowtls'}
# Deliberately conservative. Newer clients support more; require a versioned
# compatibility test before expanding the default all-in-one share-link list.
V2RAYN_SCHEMES = {'vless', 'vmess', 'trojan', 'ss'}


class ProfileError(ValueError):
    """Messages must never include profile content or credentials."""


def decode64(text: str) -> str:
    try:
        return base64.b64decode(text + '=' * (-len(text) % 4),
                               altchars=b'-_', validate=True).decode('utf-8')
    except (ValueError, UnicodeError) as exc:
        raise ProfileError('Invalid base64/UTF-8 payload') from exc


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProfileError('Duplicate JSON property')
        result[key] = value
    return result


def json_document(text):
    try:
        return json.loads(text, object_pairs_hook=unique_object,
                          parse_constant=lambda _: (_ for _ in ()).throw(
                              ProfileError('Non-finite JSON number')))
    except (ValueError, RecursionError) as exc:
        raise ProfileError('Invalid or ambiguous JSON document') from exc


@dataclass(frozen=True)
class Profile:
    content: str
    format: str
    engine: str
    protocol: str
    canonical: str
    v2rayn: bool = False

    @property
    def identity(self):
        return hashlib.sha256((self.format + '\0' + self.canonical).encode()).hexdigest()


def share_link(text: str) -> Profile:
    scheme = text.split(':', 1)[0].lower()
    if scheme not in URI_PROTOCOLS:
        raise ProfileError('Unsupported URI scheme (Hysteria v1 is not Hysteria2)')
    if any(c.isspace() or ord(c) < 32 for c in text):
        raise ProfileError('Whitespace/control character in share link')
    normalized = scheme + text[len(scheme):]
    try:
        if scheme == 'vmess':
            data = json_document(decode64(normalized.split('://', 1)[1]))
            if not isinstance(data, dict) or not data.get('add') or not data.get('id'):
                raise ProfileError('VMess needs server and identity')
            if not 1 <= int(data.get('port', 0)) <= 65535:
                raise ProfileError('Invalid VMess port')
            canonical = json.dumps(data, sort_keys=True, separators=(',', ':'))
        else:
            uri = urlsplit(normalized)
            # Legacy SS base64 encodes the entire authority.
            if scheme == 'ss' and '@' not in uri.netloc:
                authority = decode64(uri.netloc)
                uri = urlsplit('ss://' + authority)
            if not uri.hostname or not uri.username or not uri.port:
                raise ProfileError('Share link needs credential, host and explicit port')
            if not 1 <= uri.port <= 65535:
                raise ProfileError('Invalid share-link port')
            canonical = normalized
    except (ValueError, TypeError, IndexError) as exc:
        raise ProfileError('Invalid share-link structure') from exc
    protocol = {'ss': 'shadowsocks', 'hy2': 'hysteria2'}.get(scheme, scheme)
    engine = 'xray' if scheme in V2RAYN_SCHEMES else 'sing-box'
    return Profile(normalized + '\n', 'uri', engine, protocol, canonical,
                   scheme in V2RAYN_SCHEMES)


def wg_document(text: str) -> Profile:
    sections = []
    current = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(('#', ';')):
            continue
        if line.startswith('['):
            name = line.lower()
            if name not in ('[interface]', '[peer]'):
                raise ProfileError('Unknown WireGuard section')
            current = (name, {})
            sections.append(current)
            continue
        if current is None or '=' not in line:
            raise ProfileError('Malformed WireGuard directive')
        key, value = (part.strip() for part in line.split('=', 1))
        key = key.lower()
        if key in current[1]:
            raise ProfileError('Duplicate WireGuard directive')
        current[1][key] = value
    if not sections or sections[0][0] != '[interface]':
        raise ProfileError('Missing WireGuard interface')
    if sum(name == '[interface]' for name, _ in sections) != 1:
        raise ProfileError('Expected one interface per file')
    interface = sections[0][1]
    peers = [data for name, data in sections if name == '[peer]']
    if not peers or not interface.get('address'):
        raise ProfileError('WireGuard requires interface addresses and peers')
    def check_key(value):
        try:
            if len(base64.b64decode(value, validate=True)) != 32:
                raise ValueError()
        except ValueError as exc:
            raise ProfileError('WireGuard key must encode 32 bytes') from exc
    check_key(interface.get('privatekey', ''))
    try:
        for address in interface['address'].split(','):
            ipaddress.ip_interface(address.strip())
        for peer in peers:
            check_key(peer.get('publickey', ''))
            if 'presharedkey' in peer:
                check_key(peer['presharedkey'])
            if not peer.get('allowedips'):
                raise ProfileError('Peer needs AllowedIPs')
            for route in peer['allowedips'].split(','):
                ipaddress.ip_network(route.strip(), strict=False)
            if 'endpoint' in peer:
                endpoint = urlsplit('udp://' + peer['endpoint'])
                if not endpoint.hostname or not endpoint.port or not 1 <= endpoint.port <= 65535:
                    raise ProfileError('Invalid peer endpoint')
    except ValueError as exc:
        raise ProfileError('Invalid WireGuard address, key or peer') from exc
    # Keep every directive, peer, comment and AWG expression verbatim. No
    # invented defaults or unsafe AWG -> WG conversion.
    awg = any(key in AWG_KEYS for _, values in sections for key in values)
    protocol = 'amneziawg' if awg else 'wireguard'
    return Profile(text, 'conf', protocol, protocol, text)


def yaml_document(text):
    try:
        import yaml
    except ImportError as exc:
        raise ProfileError('YAML requires tool/requirements-config.txt') from exc
    class StrictLoader(yaml.SafeLoader):
        pass
    def mapping(loader, node):
        return unique_object([(loader.construct_object(k), loader.construct_object(v))
                              for k, v in node.value])
    StrictLoader.add_constructor('tag:yaml.org,2002:map', mapping)
    try:
        depth = 0
        for event in yaml.parse(text):
            if isinstance(event, yaml.AliasEvent) or getattr(event, 'anchor', None):
                raise ProfileError('YAML aliases/anchors are not accepted')
            if isinstance(event, (yaml.MappingStartEvent, yaml.SequenceStartEvent)):
                depth += 1
                if depth > 64:
                    raise ProfileError('YAML nesting limit exceeded')
            if isinstance(event, (yaml.MappingEndEvent, yaml.SequenceEndEvent)):
                depth -= 1
        return yaml.load(text, Loader=StrictLoader)
    except (yaml.YAMLError, TypeError, ValueError, RecursionError) as exc:
        raise ProfileError('Invalid or unsafe YAML document') from exc


def _parse_profiles(text: str, hint: str, depth: int = 0) -> list[Profile]:
    if depth > 8:
        raise ProfileError('Batch nesting limit exceeded')
    if len(text.encode('utf-8')) > MAX_BYTES:
        raise ProfileError('Input exceeds 8 MiB limit')
    text = text.lstrip('\ufeff').strip() + '\n'
    if not text.strip() or '\0' in text:
        raise ProfileError('Empty input or NUL character')
    if hint in ('wireguard', 'amneziawg') or re.search(r'^\[interface\]', text, re.I | re.M):
        profile = wg_document(text)
        if hint in ('wireguard', 'amneziawg') and profile.engine != hint:
            raise ProfileError('WireGuard/AmneziaWG identity does not match hint')
        return [profile]
    if hint == 'openvpn' or re.search(r'^(client|remote\s+|dev\s+tun)', text, re.M):
        if not re.search(r'^remote\s+\S+', text, re.M):
            raise ProfileError('OpenVPN requires a remote directive')
        # Never execute hooks, read referenced files, or embed key paths.
        return [Profile(text, 'ovpn', 'openvpn', 'openvpn', text)]
    if text.startswith(('{', '[')):
        data = json_document(text)
        if isinstance(data, list) and all(isinstance(x, str) for x in data):
            # The app exports raw full documents as well as URIs. Preserve each
            # document rather than incorrectly treating WG/YAML as share links.
            profiles = []
            for item in data:
                profiles.extend(_parse_profiles(item, hint, depth + 1))
                if len(profiles) > MAX_PROFILES:
                    raise ProfileError('Input needs 1–1000 profiles')
            if not profiles:
                raise ProfileError('Empty profile array')
            return profiles
        if not isinstance(data, dict):
            raise ProfileError('Expected an engine JSON object')
        if any(key in data for key in ('proxies', 'proxy-providers', 'proxy-groups')):
            if 'outbounds' in data:
                raise ProfileError('Ambiguous mixed-engine JSON document')
            if not (data.get('proxies') or data.get('proxy-providers')):
                raise ProfileError('Mihomo needs proxies or proxy-providers')
            if 'proxies' in data and not isinstance(data['proxies'], list):
                raise ProfileError('Mihomo proxies must be a list')
            if 'proxy-providers' in data and not isinstance(data['proxy-providers'], dict):
                raise ProfileError('Mihomo providers must be a map')
            canonical = json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
            return [Profile(text, 'json', 'mihomo', 'mixed', canonical)]
        outbounds = data.get('outbounds', [])
        if not isinstance(outbounds, list) or not outbounds:
            raise ProfileError('Engine document needs outbounds')
        if hint in ('xray', 'sing-box'):
            engine = hint
        elif all(isinstance(o, dict) and 'type' in o and 'protocol' not in o for o in outbounds):
            engine = 'sing-box'
        elif all(isinstance(o, dict) and 'protocol' in o and 'type' not in o for o in outbounds):
            engine = 'xray'
        else:
            raise ProfileError('Ambiguous engine JSON; specify --engine')
        key = 'type' if engine == 'sing-box' else 'protocol'
        if not all(isinstance(o, dict) and isinstance(o.get(key), str) for o in outbounds):
            raise ProfileError('Invalid outbound discriminator')
        canonical = json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
        return [Profile(text, 'json', engine, 'mixed', canonical)]
    if hint == 'mihomo' or re.search(r'^(proxies|proxy-providers|proxy-groups):', text, re.M):
        data = yaml_document(text)
        if not isinstance(data, dict) or not (data.get('proxies') or data.get('proxy-providers')):
            raise ProfileError('Mihomo needs proxies or proxy-providers')
        if 'proxies' in data and not isinstance(data['proxies'], list):
            raise ProfileError('Mihomo proxies must be a list')
        # YAML is retained verbatim; keys/providers/rules are not flattened.
        return [Profile(text, 'yaml', 'mihomo', 'mixed', text)]
    lines = [line.strip() for line in text.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if lines and all('://' in line for line in lines):
        return [share_link(line) for line in lines]
    # Plain base64 subscriptions only, one level to bound recursion.
    decoded = decode64(''.join(lines))
    links = decoded.splitlines()
    if not links or not all('://' in line for line in links if line.strip()):
        raise ProfileError('Unsupported subscription content')
    return [share_link(line.strip()) for line in links if line.strip()]


def parse_profiles(text: str, hint: str = 'auto') -> list[Profile]:
    profiles = _parse_profiles(text, hint)
    if not profiles or len(profiles) > MAX_PROFILES:
        raise ProfileError('Input needs 1–1000 profiles')
    if hint != 'auto' and any(p.engine != hint for p in profiles):
        raise ProfileError('Detected engine does not match explicit hint')
    return profiles


def write_package(profiles: list[Profile], destination: Path, server: str = 'unassigned') -> dict:
    if not profiles or len(profiles) > MAX_PROFILES:
        raise ProfileError('Package needs 1–1000 profiles')
    if server not in {'unassigned', 'frankfurt-1', 'frankfurt-2', 'netherlands'}:
        raise ProfileError('Unknown server category')
    # mkdir is exclusive: NEVER overwrite an earlier package or follow its symlink.
    destination.mkdir(mode=0o700, parents=False, exist_ok=False)
    def private_write(name, content):
        fd = os.open(destination / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(content)
    manifest = {'schema': 1, 'validation': 'structural-only', 'connectionTested': False,
                'serverAssignment': server, 'serverAssignmentVerified': False,
                'secretMaterial': True, 'files': [], 'duplicatesRemoved': 0}
    try:
        seen = set()
        v2rayn = []
        for profile in profiles:
            if profile.identity in seen:
                manifest['duplicatesRemoved'] += 1
                continue
            seen.add(profile.identity)
            filename = f'{len(seen):04d}-{profile.engine}.{profile.format}'
            private_write(filename, profile.content)
            manifest['files'].append({'file': filename, 'engine': profile.engine,
                                      'protocol': profile.protocol, 'format': profile.format,
                                      'v2rayNShareList': profile.v2rayn,
                                      'application': 'v2rayN share-link importer' if profile.v2rayn
                                      else profile.engine + ' compatible client (version check required)'})
            if profile.v2rayn:
                v2rayn.append(profile.content.strip())
        private_write('v2rayn.txt', '\n'.join(v2rayn) + ('\n' if v2rayn else ''))
        manifest['v2rayN'] = {'file': 'v2rayn.txt', 'profiles': len(v2rayn),
                             'scope': 'VLESS/VMess/Trojan/SS share links only; target version and engine must support transport/cipher'}
        # Written last: absence means an incomplete package, never usable evidence.
        private_write('manifest.json', json.dumps(manifest, indent=2) + '\n')
    except BaseException:
        shutil.rmtree(destination)
        raise
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='+', type=Path)
    parser.add_argument('--output', required=True, type=Path, help='NEW private directory; parent must exist')
    parser.add_argument('--engine', default='auto', choices=['auto', 'xray', 'sing-box', 'mihomo', 'wireguard', 'amneziawg', 'openvpn'])
    parser.add_argument('--server', default='unassigned', choices=['unassigned', 'frankfurt-1', 'frankfurt-2', 'netherlands'])
    args = parser.parse_args(argv)
    try:
        profiles = []
        if len(args.inputs) > MAX_PROFILES:
            raise ProfileError('Too many input files')
        total = 0
        for path in args.inputs:
            with path.open('rb') as stream:
                raw = stream.read(MAX_BYTES + 1)
            total += len(raw)
            if len(raw) > MAX_BYTES or total > 64 * 1024 * 1024:
                raise ProfileError('Input size limit exceeded')
            profiles.extend(parse_profiles(raw.decode('utf-8'), args.engine))
            if len(profiles) > MAX_PROFILES:
                raise ProfileError('Too many profiles')
        manifest = write_package(profiles, args.output, args.server)
        print(f"Packaged {len(manifest['files'])} profiles; structural checks only. Output contains secrets.")
        return 0
    except (ProfileError, OSError, UnicodeError, RecursionError) as exc:
        # OS errors may contain secret filenames. Never echo input or exception repr.
        print('Packaging failed: ' + (str(exc) if isinstance(exc, ProfileError)
                                      else 'file access, encoding or resource error'), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
