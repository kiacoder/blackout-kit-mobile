#!/usr/bin/env bash
# Synthetic credentials only. Server must run in a dedicated container with
# forwarding disabled and ports published to host loopback only.
set -euo pipefail
umask 077
[[ "$(cat /proc/sys/net/ipv4/ip_forward)" == 0 ]] || { echo 'Refusing forwarding-enabled server'; exit 2; }
mode="${1:-cert}"
transport="${2:-tcp}"
case "$mode" in cert|encrypted-login|login-only|hold) ;; *) exit 2 ;; esac
case "$transport" in tcp|udp) ;; *) exit 2 ;; esac
work="$(mktemp -d)"
server_pid=
echo_pid=
cleanup() {
  if [[ -n "$echo_pid" ]]; then kill "$echo_pid" 2>/dev/null || true; wait "$echo_pid" 2>/dev/null || true; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
cd "$work"
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 1 -subj /CN=FixtureCA >/dev/null 2>&1
for role in server client; do
  openssl req -newkey rsa:2048 -nodes -keyout "$role.key" -out "$role.csr" -subj "/CN=$role" >/dev/null 2>&1
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=%sAuth\n' "$role" > "$role.ext"
  openssl x509 -req -in "$role.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -out "$role.pem" -days 1 -extfile "$role.ext" >/dev/null 2>&1
done
openssl pkcs8 -topk8 -in client.key -out encrypted.key -v2 aes-256-cbc -passout pass:fixture-key-password
cat > verify-login <<'AUTH'
#!/bin/sh
[ ! -f stop-server ] && [ "$(sed -n '1p' "$1")" = fixture-user ] && [ "$(sed -n '2p' "$1")" = fixture-password ]
AUTH
chmod 700 verify-login
extra=()
if [[ "$mode" == encrypted-login || "$mode" == login-only || "$mode" == hold ]]; then
  extra+=(--script-security 2 --auth-user-pass-verify "$work/verify-login" via-file)
fi
if [[ "$mode" == login-only ]]; then
  extra+=(--verify-client-cert none --username-as-common-name)
fi
server_proto=udp
client_proto=udp
if [[ "$transport" == tcp ]]; then server_proto=tcp-server; client_proto=tcp-client; fi
cat > echo.py <<'PY'
import socket
import struct
import threading
from pathlib import Path

def tcp_echo():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("10.77.0.1", 41004))
        listener.listen(4)
        while True:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(5)
                try:
                    while True:
                        data = conn.recv(2048)
                        if not data:
                            break
                        conn.sendall(data)
                except (TimeoutError, ConnectionResetError, BrokenPipeError):
                    pass

def stop_control():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.bind(("10.77.0.1", 41005))
        while True:
            data, addr = udp.recvfrom(64)
            if data == b"stop-synthetic-server":
                udp.sendto(data, addr)
                Path("stop-server").touch()

def dns_echo(address):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.bind((address, 53))
        while True:
            data, addr = udp.recvfrom(2048)
            if len(data) < 17:
                continue
            # Accept only the one synthetic question, never relay requests.
            question = b"\x10blackout-fixture\x04test\x00\x00\x01\x00\x01"
            if data[12:12+len(question)] != question:
                continue
            header = data[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0)
            answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 0, 4) + socket.inet_aton("192.0.2.53")
            udp.sendto(header + question + answer, addr)

threading.Thread(target=dns_echo, args=("10.77.0.1",), daemon=True).start()
threading.Thread(target=dns_echo, args=("10.77.0.53",), daemon=True).start()
threading.Thread(target=tcp_echo, daemon=True).start()
threading.Thread(target=stop_control, daemon=True).start()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
    udp.bind(("10.77.0.1", 41002))
    while True:
        data, addr = udp.recvfrom(2048)
        udp.sendto(data, addr)
PY
openvpn --dev tun0 --disable-dco --port 11940 --proto "$server_proto" \
  --topology subnet --server 10.77.0.0 255.255.255.0 --ca ca.pem --cert server.pem --key server.key \
  --dh none --tls-version-min 1.2 --data-ciphers AES-256-GCM:AES-128-GCM \
  --push 'redirect-gateway def1' --push 'dhcp-option DNS 10.77.0.1' \
  --keepalive 2 8 --verb 3 "${extra[@]}" > server.log 2>&1 &
server_pid=$!
for i in $(seq 1 100); do
    kill -0 "$server_pid" 2>/dev/null || { tail -20 server.log; exit 1; }
    grep -q 'Initialization Sequence Completed' server.log && break
    sleep .1
done
grep -q 'Initialization Sequence Completed' server.log
ip addr add 10.77.0.53/32 dev tun0
python3 echo.py &
echo_pid=$!
sleep .3
kill -0 "$echo_pid"
{
  printf 'client\ndev tun\nproto %s\nremote 10.0.2.2 11940\nremote-cert-tls server\nverify-x509-name server name\n' "$client_proto"
  printf '<ca>\n'; cat ca.pem; printf '</ca>\n'
  if [[ "$mode" != login-only ]]; then
    printf '<cert>\n'; cat client.pem; printf '</cert>\n<key>\n'
    if [[ "$mode" == encrypted-login ]]; then cat encrypted.key; else cat client.key; fi
    printf '</key>\n'
  fi
  if [[ "$mode" == encrypted-login || "$mode" == login-only || "$mode" == hold ]]; then printf 'auth-user-pass\n'; fi
} > /fixture/profile.tmp
mv /fixture/profile.tmp /fixture/profile.ovpn
echo 'SYNTHETIC_ANDROID_FIXTURE_READY'
# Bounded lifetime; no daemon survives the test container.
for i in $(seq 1 300); do
  if [[ "$mode" == hold && -f stop-server && ! -f server-restarted ]]; then
    # Restart the VPN server but keep the TCP endpoint reachable. The
    # fixture auth script now rejects all reauthentication.
    kill -USR1 "$server_pid"
    touch server-restarted
    echo 'SYNTHETIC_SERVER_REAUTH_REJECTED'
  fi
  if [[ -n "$server_pid" ]]; then kill -0 "$server_pid" || exit 1; fi
  kill -0 "$echo_pid" || exit 1
  sleep 1
done
