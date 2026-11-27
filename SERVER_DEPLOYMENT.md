# Three-server deployment report — 2026-11-16

Historical deployment report; no new server inventory or deployment was verified in this documentation update. See [current status](CURRENT_STATUS.md).

| Category | Location / address | Inventory | Changes | Working profiles generated |
|---|---|---|---|---|
| frankfurt-1 | Frankfurt / [private Frankfurt-1 address] | Not accessed | None | None |
| frankfurt-2 | Frankfurt / [private Frankfurt-2 address] | Not accessed | None | None |
| netherlands | Netherlands / [private Netherlands address] | Not accessed | None | None |

OS/architecture, versions, services, inbounds/ports, firewall, certificate dates,
profiles, logs, broken deployments and installation capacity are **unknown** on all
three. No active scans, SSH attempts, service changes, certificates or keys generated.
No v2rayN package from real deployments exists. An IP does not specify protocol,
authentication, domain/SNI, certificate trust, REALITY parameters or server routes.

## Access needed (secure channel, not chat or Git)
* Reachable authorized development environment/network path to each server.
* SSH account and port, trusted host-key fingerprints from an independent channel,
  authorized SSH agent/key mounted securely, and specific sudo scope if necessary.
* Confirmation of which services/profiles must remain unchanged and maintenance window.
* Private backup destination, rollback owner and restore test process.
* Authorized client credentials/configs through protected files; do not paste secrets
  into chat. DNS names, certificate ownership and renewal method without private keys.

The current sandbox egress allowlist does not include these addresses. Do not try to
circumvent it. GitHub access does not imply server authorization or server credentials.

## Read-only audit, then additive deployment
1. Record OS release, uname architecture, RAM/free disk and engine `version` output.
2. Record listening ports (`ss -lntu`) and named service status. Inspect unit definitions
   privately: command lines and environment may contain secrets.
3. Inspect nftables/iptables/UFW and routes without changing them. Confirm management
   access remains allowed. Read certificate subject/expiry, never copy private keys.
4. Inventory existing configs in a root-only location; redact log excerpts locally.
   Do not commit full journal output, profiles, process command lines or environment.
5. Back up unit/config/firewall files with permissions intact to encrypted restricted
   storage; verify restore before any write. Record checksums privately.
6. Pin new binaries/source/license notices; use new service users, files and unoccupied
   ports. Validate native configs before launch; no replacement of existing listeners.
7. Test one engine/server at a time: handshake, DNS, IPv4/IPv6 egress, reconnect,
   routing and existing profiles. Stop/revert only the new deployment on failure.
8. Export authorized client profiles through the offline factory, label engine-native
   validation and actual connectivity separately, then produce consolidated/companion
   collections on the user's machine. Do not substitute sample endpoints for real ones.

Milestone 2 access check: no SSH directory or SSH agent socket is present. Network
restrictions still exclude the three addresses. No server connections or deployments
were attempted; all inventory and profile-generation statuses above remain unchanged.
