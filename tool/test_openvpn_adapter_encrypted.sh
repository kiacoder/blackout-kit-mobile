#!/usr/bin/env bash
set -euo pipefail
umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
openssl req -x509 -newkey rsa:2048 -keyout "$work/key.pem" -out "$work/cert.pem" -days 1 -subj /CN=fixture -passout pass:fixture-key-password >/dev/null 2>&1
{
  printf 'client\ndev tun\nproto udp\nremote 127.0.0.1 1194\nremote-cert-tls server\n<ca>\n'
  cat "$work/cert.pem"
  printf '</ca>\n<cert>\n'
  cat "$work/cert.pem"
  printf '</cert>\n<key>\n'
  cat "$work/key.pem"
  printf '</key>\n'
} > "$work/profile.ovpn"
"$1" "$work/profile.ovpn"
