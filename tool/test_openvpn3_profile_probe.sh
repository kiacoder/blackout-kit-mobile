#!/usr/bin/env bash
# Synthetic fixtures, no network, no real profile or credential.
set -euo pipefail
probe=${1:?Provide the compiled host probe}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=fixture.test \
  -keyout "$work/key" -out "$work/ca" >/dev/null 2>&1
{
  printf '%s\n' 'client' 'dev tun' 'proto udp' 'remote fixture.test 1194' 'remote-cert-tls server' '<ca>'
  cat "$work/ca"
  printf '%s\n' '</ca>' 'auth-user-pass'
} > "$work/valid"
result=$("$probe" < "$work/valid")
[[ "$result" == "PARSED auth=interactive "* ]]
echo "PASS native interactive profile evaluation"
{
  sed '/^auth-user-pass$/d' "$work/valid"
  printf '%s\n' '<cert>'
  cat "$work/ca"
  printf '%s\n' '</cert>' '<key>'
  cat "$work/key"
  printf '%s\n' '</key>'
} > "$work/autologin"
result=$("$probe" < "$work/autologin")
[[ "$result" == "PARSED auth=auto "* ]]
echo "PASS native certificate-only profile evaluation"
for kind in empty missing-remote external-file oversized; do
  case "$kind" in
    empty) : > "$work/invalid" ;;
    missing-remote) printf '%s\n' 'client' 'dev tun' > "$work/invalid" ;;
    external-file) printf '%s\n' 'client' 'dev tun' 'remote fixture.test 1194' "ca $work/ca" > "$work/invalid" ;;
    oversized) head -c 1048577 /dev/zero > "$work/invalid" ;;
  esac
  if result=$("$probe" < "$work/invalid"); then
    echo "FAIL: accepted $kind" >&2
    exit 1
  fi
  [[ "$result" == "REJECTED" ]]
  echo "PASS rejects $kind"
done
echo 'Host profile evaluation only; no tunnel was created.'
