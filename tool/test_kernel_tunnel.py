#!/usr/bin/env python3
"""Real Linux kernel-TUN forwarding in disposable network namespaces.

Requires passwordless sudo, unshare, nsenter, ip and a locally built test peer.
Never uses host routes, deployment profiles, external servers or Android devices.
The unprivileged entry point ALWAYS creates a fresh network namespace first.
"""
import argparse
import http.client
import http.server
import json
import os
from pathlib import Path
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time


class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'BLACKOUT_KERNEL_TUN_FIXTURE'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        packet, sock = self.request
        answer = b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 30, 4) + socket.inet_aton('10.91.0.2')
        reply = packet[:2] + b'\x81\x80' + struct.pack('!HHHH', 1, 1, 0, 0) + packet[12:] + answer
        sock.sendto(reply, self.client_address)


def fixture_server():
    dns = socketserver.UDPServer(('10.91.0.2', 15353), DNS)
    threading.Thread(target=dns.serve_forever, daemon=True).start()
    http.server.ThreadingHTTPServer(('10.91.0.2', 18080), HTTP).serve_forever()


def inside(binary, engine, parent_inode):
    current_inode = os.stat('/proc/self/ns/net').st_ino
    if (os.geteuid() != 0 or current_inode == parent_inode or
            current_inode == os.stat('/proc/1/ns/net').st_ino):
        raise RuntimeError('Refusing to alter the caller or init network namespace')
    processes = []
    tests = []
    stats = []
    def abort(*_):
        raise RuntimeError('Fixture deadline exceeded')
    signal.signal(signal.SIGALRM, abort)
    signal.alarm(90)
    def command(args, remote=False, check=True):
        prefix = ['nsenter', '-t', str(anchor.pid), '-n'] if remote else []
        return subprocess.run(prefix + args, check=check, capture_output=True, timeout=5)
    def start(args, remote=False):
        prefix = ['nsenter', '-t', str(anchor.pid), '-n'] if remote else []
        process = subprocess.Popen(prefix + args, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        processes.append(process)
        return process
    def stop(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(3)
                raise RuntimeError('Fixture needed forced termination')
    def wait_for(check, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if check():
                    return
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(0.05)
        raise RuntimeError('Fixture readiness/forwarding timeout')
    def tcp():
        connection = http.client.HTTPConnection('10.91.0.2', 18080, timeout=1)
        try:
            connection.request('GET', '/')
            return connection.getresponse().read() == b'BLACKOUT_KERNEL_TUN_FIXTURE'
        finally:
            connection.close()
    def dns():
        query = b'\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07fixture\x04test\0\0\x01\0\x01'
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(2)
            sock.sendto(query, ('10.91.0.2', 15353))
            reply, _ = sock.recvfrom(4096)
        return reply[:2] == b'\x12\x34' and reply.endswith(socket.inet_aton('10.91.0.2'))
    anchor = None
    try:
        anchor = start(['unshare', '--net', 'sleep', '100'])
        wait_for(lambda: os.stat(f'/proc/{anchor.pid}/ns/net').st_ino != os.stat('/proc/self/ns/net').st_ino)
        command(['ip', 'link', 'add', 'outer-a', 'type', 'veth', 'peer', 'name', 'outer-b'])
        command(['ip', 'link', 'set', 'outer-b', 'netns', str(anchor.pid)])
        for remote, name, ip in [(False, 'outer-a', '172.30.77.1'), (True, 'outer-b', '172.30.77.2')]:
            command(['ip', 'link', 'set', 'lo', 'up'], remote)
            command(['ip', 'addr', 'add', ip + '/24', 'dev', name], remote)
            command(['ip', 'link', 'set', name, 'up'], remote)
        keys = [json.loads(subprocess.check_output([binary, 'keygen'], timeout=5)) for _ in range(2)]
        with tempfile.TemporaryDirectory(prefix='blackout-kernel-') as directory:
            configs = []
            for n in range(2):
                settings = f"private_key={keys[n]['private']}\nlisten_port=51820\n"
                if engine == 'awg':
                    settings += ('jc=3\njmin=64\njmax=128\ns1=15\ns2=18\ns3=20\ns4=25\n'
                                 'h1=123456-123500\nh2=67543-67550\nh3=123123-123200\nh4=32345-32350\n'
                                 'i1=<b 0xf6ab><t><r 10>\ni2=<rc 10>\ni3=<rd 10>\ni4=<r 20>\ni5=<r 25>\n')
                peer_ip = '10.91.0.2' if n == 0 else '10.91.0.1'
                endpoint = '172.30.77.2' if n == 0 else '172.30.77.1'
                settings += (f"replace_peers=true\npublic_key={keys[1-n]['public']}\n"
                             f'endpoint={endpoint}:51820\nallowed_ip={peer_ip}/32\npersistent_keepalive_interval=1\n')
                path = Path(directory) / f'peer-{n}.conf'
                path.touch(mode=0o600)
                path.write_text(settings)
                configs.append(str(path))
            for cycle in range(3):
                peers = [start([binary, 'bk0', configs[0]]), start([binary, 'bk0', configs[1]], True)]
                for remote, ip, peer_ip in [(False, '10.91.0.1', '10.91.0.2'), (True, '10.91.0.2', '10.91.0.1')]:
                    wait_for(lambda remote=remote: command(['ip', 'link', 'show', 'dev', 'bk0'], remote, False).returncode == 0)
                    command(['ip', 'addr', 'add', ip + '/32', 'dev', 'bk0'], remote)
                    command(['ip', 'link', 'set', 'bk0', 'up'], remote)
                    command(['ip', 'route', 'add', peer_ip + '/32', 'dev', 'bk0'], remote)
                if cycle == 0:
                    start([sys.executable, str(Path(__file__).resolve()), '--serve'], True)
                wait_for(tcp)
                if not dns():
                    raise RuntimeError('DNS payload mismatch')
                tests.extend([f'cycle-{cycle+1}: TCP through kernel TUN', f'cycle-{cycle+1}: UDP DNS through kernel TUN'])
                row = json.loads(command(['ip', '-j', '-s', 'link', 'show', 'dev', 'bk0']).stdout)[0]
                counters = row.get('stats64', row.get('stats'))
                if not counters or counters['rx']['bytes'] == 0 or counters['tx']['bytes'] == 0:
                    raise RuntimeError('No bidirectional kernel TUN counters')
                stats.append({'cycle': cycle+1, 'rxBytes': counters['rx']['bytes'], 'txBytes': counters['tx']['bytes']})
                if cycle == 0:
                    command(['ip', 'link', 'set', 'outer-a', 'down'])
                    forwarded = False
                    try:
                        forwarded = tcp()
                    except (OSError, http.client.HTTPException):
                        pass
                    if forwarded:
                        raise RuntimeError('Traffic unexpectedly bypassed disabled outer link')
                    command(['ip', 'link', 'set', 'outer-a', 'up'])
                    wait_for(tcp)
                    tests.append('outer link outage blocks traffic; recovery forwards again')
                for peer in peers:
                    stop(peer)
                for remote in [False, True]:
                    if command(['ip', 'link', 'show', 'dev', 'bk0'], remote, False).returncode == 0:
                        raise RuntimeError('Kernel TUN leaked after shutdown')
                tests.append(f'cycle-{cycle+1}: both kernel TUNs removed on shutdown')
        return {'engine': engine, 'scope': 'Linux isolated kernel TUN; NOT Android',
                'passed': True, 'checks': tests, 'tunCounters': stats}
    finally:
        signal.alarm(0)
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--engine', choices=['awg', 'wireguard'])
    parser.add_argument('--inside', type=int)
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.serve:
        if os.geteuid() != 0 or os.stat('/proc/self/ns/net').st_ino == os.stat('/proc/1/ns/net').st_ino:
            parser.error('Fixture server must run inside the isolated test namespace')
        fixture_server()
        return
    if not args.binary or not args.engine:
        parser.error('--binary and --engine required')
    if args.inside is not None:
        try:
            result = inside(str(args.binary.resolve()), args.engine, args.inside)
        except Exception as error:
            # Never report private generated configurations or subprocess output.
            print(json.dumps({'engine': args.engine, 'passed': False, 'errorType': type(error).__name__,
                              'message': str(error) if isinstance(error, RuntimeError) else 'Fixture setup or execution failed'}))
            raise SystemExit(1)
        print(json.dumps(result))
        return
    command = ['sudo', '-n', 'unshare', '--net', sys.executable, str(Path(__file__).resolve()),
               '--binary', str(args.binary.resolve()), '--engine', args.engine,
               '--inside', str(os.stat('/proc/self/ns/net').st_ino)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=110)
    if result.stdout:
        report = json.loads(result.stdout)
    else:
        report = {'engine': args.engine, 'passed': False, 'message': 'Namespace launch failed; inspect local permissions'}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
