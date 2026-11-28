"""Local synthetic SOCKS5 upstream. Never connects to requested destinations."""
import socket
import socketserver
import struct
import threading

PORT = 11940
ECHO = "192.0.2.80"
DNS = "192.0.2.53"

def exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError
        data += chunk
    return data

class Client(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(10)
        try:
            prefix = exact(sock, 2)
            if prefix == b"BK":
                if exact(sock, 6) == b"CHECK!":
                    sock.sendall(b"BK-OUTSIDE")
                    print("DIRECT_SENTINEL_PASS", flush=True)
                return
            version, count = prefix
            if version != 5 or 0 not in exact(sock, count):
                return
            sock.sendall(b"\x05\x00")
            version, cmd, reserved, atyp = exact(sock, 4)
            if (version, reserved, atyp) != (5, 0, 1):
                return
            ip = socket.inet_ntoa(exact(sock, 4))
            port = struct.unpack("!H", exact(sock, 2))[0]
            if cmd == 1 and (ip, port) == (ECHO, 41004):
                sock.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("0.0.0.0") + b"\x00\x00")
                payload = exact(sock, len(b"mihomo-android-fixture-echo"))
                if payload == b"mihomo-android-fixture-echo":
                    sock.sendall(payload)
                    print("TCP_FIXTURE_PASS", flush=True)
            elif cmd == 3:
                sock.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("10.0.2.2") + struct.pack("!H", PORT))
                while sock.recv(128):
                    pass
        except (OSError, EOFError):
            pass

class TCP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

class UDP(socketserver.UDPServer):
    allow_reuse_address = True

class Datagram(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        if len(data) < 10 or data[:4] != b"\x00\x00\x00\x01":
            return
        dest = socket.inet_ntoa(data[4:8])
        port = struct.unpack("!H", data[8:10])[0]
        payload = data[10:]
        if (dest, port) == (ECHO, 41002) and payload == b"mihomo-android-fixture-echo":
            response = payload
            print("UDP_FIXTURE_PASS", flush=True)
        elif (dest, port) == (DNS, 53) and payload[12:] == b"\x07fixture\x04test\x00\x00\x01\x00\x01":
            response = payload[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0) + payload[12:]
            response += b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 0, 4) + socket.inet_aton(ECHO)
            print("DNS_FIXTURE_PASS", flush=True)
        else:
            return
        sock.sendto(data[:10] + response, self.client_address)

if __name__ == "__main__":
    with TCP(("0.0.0.0", PORT), Client) as tcp, UDP(("0.0.0.0", PORT), Datagram) as udp:
        threading.Thread(target=udp.serve_forever, daemon=True).start()
        print("MIHOMO_FIXTURE_READY", flush=True)
        tcp.serve_forever()
