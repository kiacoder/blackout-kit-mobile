#!/usr/bin/env bash
# Requires isolated container: --network none --cap-drop ALL --cap-add NET_ADMIN --device /dev/net/tun
set -euo pipefail
umask 077
client="$(realpath "$1")"
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
# No host networking, only loopback transport and the test server's isolated TUN.
[[ "$(ip -o link show | wc -l)" -eq 1 ]] || { echo 'Refusing non-isolated network'; exit 2; }
ip link set lo up
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 1 -subj /CN=FixtureCA >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout wrong.key -out wrong.pem -days 1 -subj /CN=UntrustedCA >/dev/null 2>&1
for role in server client; do
  openssl req -newkey rsa:2048 -nodes -keyout "$role.key" -out "$role.csr" -subj "/CN=$role" >/dev/null 2>&1
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=%sAuth\n' "$role" > "$role.ext"
  openssl x509 -req -in "$role.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -out "$role.pem" -days 1 -extfile "$role.ext" >/dev/null 2>&1
done
openssl pkcs8 -topk8 -in client.key -out encrypted.key -v2 aes-256-cbc -passout pass:fixture-key-password
cat > verify-login <<'AUTH'
#!/bin/sh
[ "$(sed -n '1p' "$1")" = fixture-user ] && [ "$(sed -n '2p' "$1")" = fixture-password ]
AUTH
chmod 700 verify-login
cat > echo.py <<'PY'
import socket
import threading

def tcp_echo():
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("10.77.0.1", 41004))
    listener.listen(4)
    while True:
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(10)
            try:
                while True:
                    data = conn.recv(2048)
                    if not data:
                        break
                    conn.sendall(data)
            except TimeoutError:
                pass

threading.Thread(target=tcp_echo, daemon=True).start()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("10.77.0.1", 41002))
while True:
    data, addr = s.recvfrom(2048)
    s.sendto(data, addr)
PY
start_server() {
  local transport="$1" auth="$2"
  local extra=()
  if [[ "$auth" != cert ]]; then
    extra+=(--script-security 2 --auth-user-pass-verify "$work/verify-login" via-file)
  fi
  if [[ "$auth" == login-only ]]; then extra+=(--verify-client-cert none --username-as-common-name); fi
  openvpn --dev tun0 --disable-dco --local 127.0.0.1 --port 11940 --proto "$transport" \
    --topology subnet --server 10.77.0.0 255.255.255.0 --ca ca.pem --cert server.pem --key server.key \
    --dh none --tls-version-min 1.2 --data-ciphers AES-256-GCM:AES-128-GCM \
    --push 'redirect-gateway def1' --push 'dhcp-option DNS 10.77.0.1' \
    --keepalive 5 20 --verb 3 "${extra[@]}" > server.log 2>&1 &
  server_pid=$!
  for i in $(seq 1 50); do
    kill -0 "$server_pid" 2>/dev/null || { echo 'Server failed'; tail -12 server.log; return 1; }
    if grep -q 'Initialization Sequence Completed' server.log; then break; fi
    sleep .1
  done
  grep -q 'Initialization Sequence Completed' server.log
  python3 echo.py > echo.log 2>&1 &
  echo_pid=$!
  sleep .2
  kill -0 "$echo_pid"
}
stop_server() {
  kill "$echo_pid"; wait "$echo_pid" || true; echo_pid=
  kill "$server_pid"; wait "$server_pid" || true; server_pid=
}
profile() {
  local transport="$1" mode="$2"
  {
    printf 'client\ndev tun\nproto %s\nremote 127.0.0.1 11940\nremote-cert-tls server\nverb 3\n' "$transport"
    if [[ "$mode" == bad-name ]]; then
      printf 'verify-x509-name wrong-server name\n'
    elif [[ "$mode" != missing-name ]]; then
      printf 'verify-x509-name server name\n'
    fi
    printf '<ca>\n'; if [[ "$mode" == bad-ca ]]; then cat wrong.pem; else cat ca.pem; fi; printf '</ca>\n'
    if [[ "$mode" != login-only ]]; then
      printf '<cert>\n'; cat client.pem; printf '</cert>\n<key>\n'
      if [[ "$mode" == encrypted || "$mode" == bad-key ]]; then cat encrypted.key; else cat client.key; fi
      printf '</key>\n'
    fi
    if [[ "$mode" == login || "$mode" == bad-login || "$mode" == login-only ]]; then printf 'auth-user-pass\n'; fi
  } > profile.ovpn
}
case_run() {
  local server_proto="$1" client_proto="$2" auth="$3" mode="$4"
  start_server "$server_proto" "$auth"
  profile "$client_proto" "$mode"
  if ! timeout 28 "$client" profile.ovpn "$mode"; then
    echo "Interop failure: $server_proto/$mode"
    head -45 server.log
    tail -18 server.log
    cat echo.log
    return 1
  fi
  stop_server
}
case_run udp udp cert cert
case_run tcp-server tcp-client cert cert
case_run udp udp cert encrypted
case_run udp udp cert bad-key
case_run udp udp login login
case_run udp udp login bad-login
case_run udp udp login-only login-only
case_run udp udp cert bad-ca
case_run udp udp cert bad-name
# The Mbed TLS overlay deliberately rejects missing explicit identity.
if [[ "${2:-}" == require-name ]]; then
  case_run udp udp cert missing-name
fi
echo 'PASS isolated OpenVPN server interoperability cases'
