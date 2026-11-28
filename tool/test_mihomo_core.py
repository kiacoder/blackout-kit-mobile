#!/usr/bin/env python3
"""Real Mihomo core integration tests. Loopback only; NOT Android/TUN/device tests.

Requires an explicitly supplied, hash-verified binary. No profile or server secrets
are used. All listeners, controller credentials and configurations are disposable.
"""
import argparse
import hashlib
import http.client
import http.server
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import socketserver
import struct
import subprocess
import tempfile
import threading
import time
import unittest

BINARY = None
OBSERVATIONS = []


def free_port(kind=socket.SOCK_STREAM):
    with socket.socket(socket.AF_INET, kind) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def read_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise ConnectionError('SOCKS connection closed')
        data.extend(part)
    return bytes(data)


class ProxyRejected(ConnectionError):
    pass


def socks_request(port, host, target_port, command=1):
    sock = socket.create_connection(('127.0.0.1', port), 3)
    sock.settimeout(3)
    try:
        sock.sendall(b'\x05\x01\x00')
        if read_exact(sock, 2) != b'\x05\x00':
            raise ProxyRejected('SOCKS authentication rejected')
        host_bytes = host.encode('ascii')
        sock.sendall(bytes([5, command, 0, 3, len(host_bytes)]) + host_bytes + struct.pack('!H', target_port))
        header = read_exact(sock, 4)
        if header[1] != 0:
            raise ProxyRejected('SOCKS request rejected')
        if header[3] == 1:
            address = socket.inet_ntop(socket.AF_INET, read_exact(sock, 4))
        elif header[3] == 4:
            address = socket.inet_ntop(socket.AF_INET6, read_exact(sock, 16))
        elif header[3] == 3:
            address = read_exact(sock, read_exact(sock, 1)[0]).decode('ascii')
        else:
            raise ProxyRejected('Invalid SOCKS address')
        bound_port = struct.unpack('!H', read_exact(sock, 2))[0]
        return sock, address, bound_port
    except BaseException:
        sock.close()
        raise


def fetch(port, host, target_port):
    sock, _, _ = socks_request(port, host, target_port)
    with sock:
        sock.sendall(b'GET /fixture HTTP/1.1\r\nHost: fixture.test\r\nConnection: close\r\n\r\n')
        result = bytearray()
        while len(result) < 65536:
            part = sock.recv(4096)
            if not part:
                break
            result.extend(part)
        return bytes(result)


class HTTPHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.hits += 1
        body = b'BLACKOUT_LOOPBACK_FIXTURE'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class HTTPFixture(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True
    hits = 0


class DNSHandler(socketserver.BaseRequestHandler):
    def handle(self):
        packet, sock = self.request
        if len(packet) < 17:
            return
        offset = 12
        while offset < len(packet) and packet[offset]:
            offset += packet[offset] + 1
        if offset + 5 > len(packet):
            return
        question = packet[12:offset + 5]
        qtype = struct.unpack('!H', packet[offset + 1:offset + 3])[0]
        self.server.requests += 1
        answer = b''
        if qtype == 1:
            answer = b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 1, 4) + socket.inet_aton('127.0.0.1')
        header = packet[:2] + b'\x81\x80' + struct.pack('!HHHH', 1, int(bool(answer)), 0, 0)
        sock.sendto(header + question + answer, self.client_address)


class UDPFixture(socketserver.UDPServer):
    allow_reuse_address = True
    requests = 0


class EchoHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        self.server.requests += 1
        sock.sendto(data, self.client_address)


def serve(server):
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.05}, daemon=True)
    thread.start()
    return server


def dns_query(name='dns-fixture.test'):
    labels = b''.join(bytes([len(part)]) + part.encode() for part in name.split('.')) + b'\0'
    return b'\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00' + labels + b'\x00\x01\x00\x01'


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='blackout-core-test-')
        self.home = Path(self.directory.name)
        self.http = serve(HTTPFixture(('127.0.0.1', 0), HTTPHandler))
        self.readiness_http = serve(HTTPFixture(('127.0.0.1', 0), HTTPHandler))
        self.dns = serve(UDPFixture(('127.0.0.1', 0), DNSHandler))
        self.echo = serve(UDPFixture(('127.0.0.1', 0), EchoHandler))
        self.socks_port = free_port()
        self.controller_port = free_port()
        self.dns_port = free_port(socket.SOCK_DGRAM)
        self.secret = secrets.token_hex(24)
        self.process = None
        self.config = {
            'socks-port': self.socks_port, 'allow-lan': False, 'bind-address': '127.0.0.1',
            'mode': 'rule', 'log-level': 'silent', 'ipv6': False,
            'external-controller': f'127.0.0.1:{self.controller_port}', 'secret': self.secret,
            'geodata-mode': False, 'geo-auto-update': False, 'tun': {'enable': False},
            'proxies': [],
            'proxy-groups': [{'name': 'select', 'type': 'select', 'proxies': ['DIRECT', 'REJECT']}],
            'rules': ['DOMAIN,blocked.test,REJECT', 'MATCH,select'],
            'dns': {'enable': True, 'listen': f'127.0.0.1:{self.dns_port}', 'ipv6': False,
                    'enhanced-mode': 'redir-host', 'use-hosts': False,
                    'nameserver': [f'udp://127.0.0.1:{self.dns.server_address[1]}'],
                    'default-nameserver': ['127.0.0.1'], 'fallback': []},
        }
    def config_fd(self):
        # The Linux fixture uses anonymous RAM-backed storage. The disposable
        # loopback controller credential never enters a named config file.
        fd = os.memfd_create('mihomo-fixture', flags=os.MFD_CLOEXEC)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(os.dup(fd), 'wb') as stream:
                stream.write(json.dumps(self.config).encode('utf-8'))
            os.lseek(fd, 0, os.SEEK_SET)
            return fd
        except BaseException:
            os.close(fd)
            raise

    def validate_config(self):
        fd = self.config_fd()
        try:
            return subprocess.run([BINARY, '-t', '-d', str(self.home),
                                   '-f', f'/proc/self/fd/{fd}'],
                                  pass_fds=(fd,), stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=10)
        finally:
            os.close(fd)

    def tearDown(self):
        try:
            self.stop()
        finally:
            for server in [self.http, self.readiness_http, self.dns, self.echo]:
                server.shutdown()
                server.server_close()
            self.directory.cleanup()

    def start(self):
        started = time.monotonic()
        fd = self.config_fd()
        try:
            self.process = subprocess.Popen([BINARY, '-d', str(self.home),
                                             '-f', f'/proc/self/fd/{fd}'],
                                            pass_fds=(fd,), stdin=subprocess.DEVNULL,
                                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        finally:
            os.close(fd)
        while time.monotonic() - started < 10:
            if self.process.poll() is not None:
                self.fail('Mihomo exited before readiness')
            try:
                # A SOCKS greeting can succeed before routing and DNS workers
                # are initialized. Use a separate disposable endpoint so the
                # readiness traffic cannot satisfy any forwarding assertion.
                tcp_ready = b'BLACKOUT_LOOPBACK_FIXTURE' in fetch(
                    self.socks_port, '127.0.0.1', self.readiness_http.server_port)
                if tcp_ready and self.dns_ready():
                    status = Path(f'/proc/{self.process.pid}/status').read_text()
                    rss = next((line for line in status.splitlines() if line.startswith('VmRSS:')), '')
                    OBSERVATIONS.append({'test': self.id().split('.')[-1],
                                         'startupMs': round((time.monotonic() - started) * 1000), 'rss': rss})
                    return
            except (OSError, ConnectionError):
                pass
            time.sleep(0.02)
        self.fail('Mihomo readiness timeout')

    def dns_ready(self):
        # Unique readiness query, separate from the DNS assertions below.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(0.2)
            sock.sendto(dns_query('readiness-fixture.test'), ('127.0.0.1', self.dns_port))
            reply, _ = sock.recvfrom(4096)
        return reply[:2] == b'\x12\x34' and socket.inet_aton('127.0.0.1') in reply

    def stop(self):
        if self.process is None:
            return
        process, self.process = self.process, None
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(2)
            self.fail('Mihomo required forced termination')

    def api(self, method, path, data=None, authenticated=True):
        connection = http.client.HTTPConnection('127.0.0.1', self.controller_port, timeout=3)
        headers = {'Content-Type': 'application/json'}
        if authenticated:
            headers['Authorization'] = 'Bearer ' + self.secret
        try:
            connection.request(method, path, json.dumps(data) if data is not None else None, headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_version_and_native_config_validation(self):
        version = subprocess.run([BINARY, '-v'], capture_output=True, text=True, timeout=5)
        self.assertEqual(version.returncode, 0)
        self.assertIn('Mihomo Meta v1.19.34 linux amd64', version.stdout)
        checked = self.validate_config()
        self.assertEqual(checked.returncode, 0)

    def test_invalid_config_is_rejected(self):
        self.config['proxies'] = [{'name': 'invalid', 'type': 'not-an-engine-type'}]
        checked = self.validate_config()
        self.assertNotEqual(checked.returncode, 0)

    def test_tcp_forwarding_by_ip(self):
        self.start()
        self.assertIn(b'BLACKOUT_LOOPBACK_FIXTURE', fetch(self.socks_port, '127.0.0.1', self.http.server_port))
        self.assertEqual(self.http.hits, 1)

    def test_tcp_forwarding_by_name_uses_configured_dns(self):
        self.start()
        before = self.dns.requests
        self.assertIn(b'BLACKOUT_LOOPBACK_FIXTURE', fetch(self.socks_port, 'fixture.test', self.http.server_port))
        self.assertGreater(self.dns.requests, before)

    def test_dns_listener_uses_loopback_upstream(self):
        self.start()
        before = self.dns.requests
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(3)
            sock.sendto(dns_query(), ('127.0.0.1', self.dns_port))
            reply, _ = sock.recvfrom(4096)
        self.assertEqual(reply[:2], b'\x12\x34')
        self.assertIn(socket.inet_aton('127.0.0.1'), reply)
        self.assertGreater(self.dns.requests, before)

    def test_domain_reject_rule_blocks_before_http(self):
        self.start()
        try:
            result = fetch(self.socks_port, 'blocked.test', self.http.server_port)
            self.assertNotIn(b'BLACKOUT_LOOPBACK_FIXTURE', result)
        except OSError:
            # A rejected or unavailable fixture connection is expected.
            pass
        self.assertEqual(self.http.hits, 0)

    def test_proxy_group_selection_changes_forwarding(self):
        self.start()
        status, data = self.api('GET', '/proxies/select')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)['now'], 'DIRECT')
        self.assertEqual(self.api('PUT', '/proxies/select', {'name': 'REJECT'})[0], 204)
        try:
            result = fetch(self.socks_port, '127.0.0.1', self.http.server_port)
            self.assertNotIn(b'BLACKOUT_LOOPBACK_FIXTURE', result)
        except OSError:
            # A rejected or unavailable fixture connection is expected.
            pass
        self.assertEqual(self.http.hits, 0)
        self.assertEqual(self.api('PUT', '/proxies/select', {'name': 'DIRECT'})[0], 204)
        self.assertIn(b'BLACKOUT_LOOPBACK_FIXTURE', fetch(self.socks_port, '127.0.0.1', self.http.server_port))

    def test_controller_requires_authentication(self):
        self.start()
        self.assertEqual(self.api('GET', '/version', authenticated=False)[0], 401)

    def test_udp_forwarding(self):
        self.start()
        control, address, port = socks_request(self.socks_port, '0.0.0.0', 0, command=3)
        with control, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
            udp.settimeout(0.5)
            self.assertTrue(ipaddress.ip_address(address).is_loopback or address == '0.0.0.0')
            header = b'\0\0\0\1' + socket.inet_aton('127.0.0.1') + struct.pack('!H', self.echo.server_address[1])
            # UDP is lossy, and TCP readiness does not prove UDP initialization.
            reply = b''
            for _ in range(6):
                udp.sendto(header + b'BLACKOUT_UDP_FIXTURE', ('127.0.0.1', port))
                try:
                    reply, _ = udp.recvfrom(4096)
                    break
                except socket.timeout:
                    continue
        self.assertTrue(reply.endswith(b'BLACKOUT_UDP_FIXTURE'))
        self.assertGreaterEqual(self.echo.requests, 1)

    def test_restart_and_shutdown_release_ports(self):
        for _ in range(3):
            self.start()
            self.assertIn(b'BLACKOUT_LOOPBACK_FIXTURE', fetch(self.socks_port, '127.0.0.1', self.http.server_port))
            self.stop()
            with self.assertRaises(OSError):
                socket.create_connection(('127.0.0.1', self.socks_port), 0.2)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.bind(('127.0.0.1', self.dns_port))

    def test_upstream_outage_and_recovery_without_core_restart(self):
        self.start()
        pid = self.process.pid
        port = self.http.server_port
        self.http.shutdown()
        self.http.server_close()
        try:
            result = fetch(self.socks_port, '127.0.0.1', port)
            self.assertNotIn(b'BLACKOUT_LOOPBACK_FIXTURE', result)
        except OSError:
            # A rejected or unavailable fixture connection is expected.
            pass
        self.http = serve(HTTPFixture(('127.0.0.1', port), HTTPHandler))
        self.assertIn(b'BLACKOUT_LOOPBACK_FIXTURE', fetch(self.socks_port, '127.0.0.1', port))
        self.assertEqual(self.process.pid, pid)
        self.assertIsNone(self.process.poll())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if hashlib.sha256(args.binary.read_bytes()).hexdigest() != args.sha256:
        parser.error('Binary checksum mismatch; refusing execution')
    BINARY = str(args.binary.resolve())
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CoreTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({'scope': 'Linux core loopback fixtures, NOT Android VPN',
                                          'tests': result.testsRun, 'passed': result.wasSuccessful(),
                                          'binarySha256': args.sha256, 'observations': OBSERVATIONS}, indent=2) + '\n')
    raise SystemExit(0 if result.wasSuccessful() else 1)
