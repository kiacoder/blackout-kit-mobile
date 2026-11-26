#!/usr/bin/env python3
"""Recover AWG's pinned Go modules through GitHub, without disabling checksum checks.

Requires Go 1.26.x (with vendored x/mod), pinned official AWG Android source,
and permitted GitHub/codeload access. Development cache only; no app modification.
"""
import argparse
import concurrent.futures
import io
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

REPOS = {
    'github.com/amnezia-vpn/amneziawg-go/v3': 'amnezia-vpn/amneziawg-go',
    'github.com/google/btree': 'google/btree',
    'go.uber.org/atomic': 'uber-go/atomic',
    'golang.org/x/crypto': 'golang/crypto',
    'golang.org/x/net': 'golang/net',
    'golang.org/x/sys': 'golang/sys',
    'golang.org/x/time': 'golang/time',
    'golang.zx2c4.com/wintun': 'nbdy/wintun-go',
    'gvisor.dev/gvisor': 'google/gvisor',
    'golang.zx2c4.com/wireguard': 'WireGuard/wireguard-go',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--engine', choices=['awg', 'wireguard'], default='awg')
    parser.add_argument('--go', default='go')
    parser.add_argument('--only', choices=REPOS)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = args.source.resolve()
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    pins = {'awg': 'ff15093bf3856fea0947923474870b86efb682f0',
            'wireguard': 'e7b3a3c118836e112620b1302a8ba1873ad4daac'}
    if revision != pins[args.engine]:
        parser.error('Unexpected official Android source revision')
    # Check the actual go.sum, not just the checkout label.
    sums = source / 'tunnel/tools/libwg-go/go.sum'
    subprocess.run(['git', '-C', str(source), 'diff', '--exit-code', 'HEAD', '--',
                    'tunnel/tools/libwg-go/go.sum', 'tunnel/tools/libwg-go/go.mod'], check=True,
                   stdout=subprocess.DEVNULL)
    cache = root / f'.cache/{args.engine}-modules'
    cache.mkdir(parents=True, exist_ok=True)
    helper = cache / 'helper'
    helper.mkdir(exist_ok=True)
    goroot = Path(subprocess.check_output([args.go, 'env', 'GOROOT'], text=True).strip())
    shutil.copytree(goroot / 'src/cmd/vendor/golang.org/x/mod', helper / 'mod', dirs_exist_ok=True)
    (helper / 'mod/go.mod').write_text('module golang.org/x/mod\n\ngo 1.26.0\n')
    (helper / 'go.mod').write_text('module local/module-verifier\n\ngo 1.26.0\nrequire golang.org/x/mod v0.0.0\nreplace golang.org/x/mod => ./mod\n')
    shutil.copyfile(root / 'tool/go_module_proxy/main.go', helper / 'main.go')
    subprocess.run([args.go, '-C', str(helper), 'build', '-o', str(helper / 'verify'), '.'], check=True)
    modules = [line.split()[:2] for line in sums.read_text().splitlines() if '/go.mod ' not in line]

    def fetch(item):
        module, version = item
        repo = REPOS[module]  # Unknown mappings fail, never guessed replacements.
        match = re.search(r'(?:-|\.)\d{14}-([0-9a-f]{12})$', version)
        ref = match.group(1) if match else version
        url = f'https://codeload.github.com/{repo}/tar.gz/{ref}'
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = response.read(128 * 1024 * 1024 + 1)
        if len(archive) > 128 * 1024 * 1024:
            raise ValueError('Source archive too large')
        with tempfile.TemporaryDirectory(dir=cache) as temp:
            directory = Path(temp)
            total = 0
            with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
                for member in tar:
                    parts = PurePosixPath(member.name).parts
                    if not parts or '..' in parts or member.name.startswith('/'):
                        raise ValueError('Unsafe archive path')
                    if member.isdir():
                        continue
                    if not member.isfile():
                        raise ValueError('Unexpected archive link/special file')
                    total += member.size
                    if total > 512 * 1024 * 1024:
                        raise ValueError('Expanded source archive too large')
                    path = directory.joinpath(*parts)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as data, path.open('wb') as output:
                        shutil.copyfileobj(data, output)
            roots = list(directory.iterdir())
            if len(roots) != 1:
                raise ValueError('Unexpected archive roots')
            subprocess.run([str(helper / 'verify'), str(roots[0]), module, version,
                            str(sums), str(cache / 'proxy')], check=True)
    if args.only:
        modules = [item for item in modules if item[0] == args.only]
    failures = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(fetch, item): item for item in modules}
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as error:
                failures += 1
                print('FAILED', *futures[future], type(error).__name__, flush=True)
    print(f'{len(modules) - failures}/{len(modules)} module archives verified', flush=True)
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
