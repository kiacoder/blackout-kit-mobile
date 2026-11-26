# Configuration formats and export factory

## Application
Existing import: proxy URIs, base64 subscriptions, JSON arrays of raw profile strings,
WG/AWG `.conf`, OpenVPN `.ovpn`, QR and files. Existing generated engine JSON is
not a general arbitrary-JSON import API. Mihomo YAML/JSON full-document import is now in application source; execution is an experimental opt-in Android adapter with no bundled binary or device verification.

New **Library → menu → Batch export all profiles** exports a snapshot of the whole
library, not the current search/filter. JSON is an array of original profile strings;
it is reimportable through the existing parser. It omits subscription/source metadata,
custom display names not encoded in the original input, rankings and settings. Exact
raw duplicates collapse. v2rayN mode includes only VLESS/VMess/Trojan/SS links and
reports omitted entries. A confirmation is required before plaintext clipboard use.
No secrets are displayed automatically. Clear clipboard history yourself afterwards.
These Flutter changes have not been compiled in the restricted environment.

## Offline factory (implemented and Python-tested)
```
python3 -m venv .venv
.venv/bin/pip install -r tool/requirements-config.txt
mkdir -p private-exports
.venv/bin/python tool/config_factory.py /secure/input/* \
  --output private-exports/collection --server frankfurt-1
```
Inputs: URI lists, base64 URI subscriptions, JSON arrays of URIs, Xray/sing-box JSON
outbound documents, Mihomo/Clash-compatible YAML, WG/AWG and OpenVPN files. Use
`--engine` for an explicit format hint (one engine per invocation when using it).
No network fetching, shell directives, provider updates or subscription refresh occurs.
No credentials/keys/server settings are generated. Input must come from an authorized
real deployment. `--server` is a user-supplied category, NOT endpoint verification.

Output directory must not exist; its parent must exist. POSIX mode 0700 directory,
0600 files. `manifest.json` is written last. Existing output/symlinks are refused.
A failed write removes only the newly-created package. Outputs contain plaintext secrets.
Use an encrypted disk and do not commit outputs. On a user's authorized local machine,
`--output "$HOME/Downloads/blackout-collection"` is possible; no user Downloads is
mounted in this sandbox. Copy the complete folder securely rather than publishing it.

`v2rayn.txt` is the conservative newline-separated share-link intersection. Empty
means zero compatible links, not success generating server profiles. Other profiles
stay in numbered companion files. Actual v2rayN/core versions must support each
transport/cipher. Raw engine documents are not flattened into links because that
would lose DNS, routing, providers and groups. The manifest identifies format,
engine, protocol/category, companion application and **structural-only** validation.
No startup/connection or production claims are emitted.

## Validation limits
JSON duplicate keys, non-finite values and ambiguous engine discrimination are
rejected; dictionaries canonicalize for dedup but source JSON is retained. WG keys
must decode to 32 bytes; addresses/routes/endpoints are checked, peers preserved.
AWG new expressions remain verbatim; exact version/parameter semantics need upstream
validation. YAML uses SafeLoader, rejects duplicate keys/aliases/anchors and deep
nesting; valid profiles using anchors must be expanded offline before packaging.
OpenVPN is preserved after a remote-directive shape check; scripts, key references,
certificates and authentication are NOT validated or executed. Never run untrusted
OpenVPN hooks merely because a file was packaged. Share-link validation is structural,
not complete UUID/cipher/TLS/transport validation. An engine checker remains mandatory.

Limits: 8 MiB per input/application export, 64 MiB cumulative CLI inputs, 1000 profiles
per CLI package. Exact source dedup for WG/AWG/YAML/OpenVPN and most URIs; no claim of
full semantic equivalence. QR/batch file UX, full metadata archives, conversion,
automatic profile updates and all-engine config generation remain incomplete.


## Milestone 2 — experimental Mihomo profile path
Mihomo documents are kept as a single profile in the existing vault and JSON batch
exports. Groups/rules/provider settings survive. Runtime normalization disables native
TUN, exposed controllers, extra proxy listeners and LAN binding; it uses the existing
loopback SOCKS bridge. Custom listeners/tunnels/scripts, file providers and fake-IP DNS
are rejected. HTTPS provider cache paths are derived from provider identity/URL, so
switching profiles cannot accidentally reuse a different provider's path.

This is NOT full native Mihomo TUN/DNS integration. OS DNS follows the existing VPN
service policy; domain-based routing may depend on the profile's sniffer and available
domain metadata. Proxy selection/controller UI, health dashboards, direct TUN and
fake-IP are not implemented. Do not assume lossless source retention means identical
semantics to a desktop configuration. A document has no single latency-probe endpoint.

The editor now has an installed-engine check action for sing-box/Mihomo. Structural
parsing is not native validation. Checks may initialize engine state or fetch engine
resources/providers; only use trusted profiles. The check does not start a VPN or
prove a handshake. Xray's bundled API has no standalone checker exposed by this app;
it returns CHECK_UNAVAILABLE rather than a fabricated success.

Continuation: the offline factory now accepts full-document app JSON batches and
Mihomo JSON objects, preserving WG/YAML/JSON contents; nested batch depth is bounded.
29 Python tests pass. Native/schema/connectivity validation remains separate.
