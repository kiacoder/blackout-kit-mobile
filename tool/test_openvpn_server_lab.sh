#!/usr/bin/env bash
# Requires isolated container: --network none --cap-drop ALL --cap-add NET_ADMIN --device /dev/net/tun
set -euo pipefail
umask 077
client="$(realpath "$1")"
work="$(mktemp -d)"
server_pid=
echo_pid=
client_pid=
cleanup() {
  if [[ -n "$client_pid" ]]; then kill "$client_pid" 2>/dev/null || true; wait "$client_pid" 2>/dev/null || true; fi
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
openvpn --genkey secret control.key
openvpn --genkey tls-crypt-v2-server control-v2-server.key
openvpn --tls-crypt-v2 control-v2-server.key --genkey tls-crypt-v2-client control-v2-client.key
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
            except (TimeoutError, ConnectionResetError, BrokenPipeError):
                pass

threading.Thread(target=tcp_echo, daemon=True).start()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("10.77.0.1", 41002))
while True:
    data, addr = s.recvfrom(2048)
    s.sendto(data, addr)
PY
start_server() {
  local transport="$1" auth="$2" mode="$3"
  local extra=()
  if [[ "$auth" != cert ]]; then
    extra+=(--script-security 2 --auth-user-pass-verify "$work/verify-login" via-file)
  fi
  if [[ "$auth" == login-only ]]; then extra+=(--verify-client-cert none --username-as-common-name); fi
  case "$mode" in
    tls-auth) extra+=(--tls-auth control.key 0) ;;
    tls-crypt) extra+=(--tls-crypt control.key) ;;
    tls-crypt-v2) extra+=(--tls-crypt-v2 control-v2-server.key) ;;
  esac
  if [[ "$mode" == tls13-no-downgrade ]]; then extra+=(--tls-version-max 1.2); fi
  local redirect='redirect-gateway def1'
  if [[ "$mode" == bypass-dns ]]; then redirect+=' bypass-dns'; fi
  if [[ "$mode" == partial-v6 ]]; then
    extra+=(--server-ipv6 2001:db8:77::/64)
  fi
  if [[ "$mode" != missing-dns ]]; then extra+=(--push 'dhcp-option DNS 10.77.0.1'); fi
  local keepalive=(5 20)
  if [[ "$mode" == server-restart ]]; then keepalive=(2 8); fi
  openvpn --dev tun0 --disable-dco --local 127.0.0.1 --port 11940 --proto "$transport" \
    --topology subnet --server 10.77.0.0 255.255.255.0 --ca ca.pem --cert server.pem --key server.key \
    --dh none --tls-version-min 1.2 --data-ciphers AES-256-GCM:AES-128-GCM \
    --push "$redirect" \
    --keepalive "${keepalive[@]}" --verb 3 "${extra[@]}" > server.log 2>&1 &
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
    case "$mode" in
      tls-auth) printf 'key-direction 1\n<tls-auth>\n'; sed -n '/^-----BEGIN /,/^-----END /p' control.key; printf '</tls-auth>\n' ;;
      tls-crypt) printf '<tls-crypt>\n'; sed -n '/^-----BEGIN /,/^-----END /p' control.key; printf '</tls-crypt>\n' ;;
      tls-crypt-v2) printf '<tls-crypt-v2>\n'; sed -n '/^-----BEGIN /,/^-----END /p' control-v2-client.key; printf '</tls-crypt-v2>\n' ;;
      tls13|tls13-no-downgrade) printf 'tls-version-min 1.3\n' ;;
    esac
  } > profile.ovpn
}
case_run() {
  local server_proto="$1" client_proto="$2" auth="$3" mode="$4"
  start_server "$server_proto" "$auth" "$mode"
  profile "$client_proto" "$mode"
  if ! timeout 55 "$client" profile.ovpn "$mode"; then
    echo "Interop failure: $server_proto/$mode"
    head -45 server.log
    tail -18 server.log
    cat echo.log
    return 1
  fi
  stop_server
}
case_run udp udp cert tls-auth
case_run udp udp cert tls-crypt
case_run udp udp cert tls-crypt-v2
case_run udp udp cert tls13
case_run udp udp cert tls13-no-downgrade
if [[ "${3:-}" == advanced-only ]]; then
  echo 'PASS advanced OpenVPN control-channel profiles'
  exit 0
fi
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
case_run udp udp cert missing-dns
case_run udp udp cert bypass-dns
case_run udp udp cert partial-v6
case_run tcp-server tcp-client cert reconnect
start_server tcp-server cert server-restart
profile tcp-client server-restart
timeout 55 "$client" profile.ovpn server-restart > recovery.log 2>&1 &
client_pid=$!
for i in $(seq 1 100); do
  if [[ -f recovery.ready ]]; then break; fi
  kill -0 "$client_pid" 2>/dev/null || { cat recovery.log; exit 1; }
  sleep .2
done
[[ -f recovery.ready ]] || { cat recovery.log; exit 1; }
stop_server
sleep 2
start_server tcp-server cert server-restart
if ! wait "$client_pid"; then
  cat recovery.log
  tail -30 server.log
  exit 1
fi
client_pid=
cat recovery.log
stop_server
echo 'PASS isolated OpenVPN server interoperability cases'
