"""Patch one pinned OpenVPN header into a build-only include overlay.

Mbed TLS 3.6.8 requires explicit hostname policy. OpenVPN verifies its
configured certificate identity via its X.509 callback instead of HTTPS
hostname matching. Require an exact configured identity before selecting that
policy; do not modify the TLS library or enable weak verification globally.
"""
import argparse
import hashlib
from pathlib import Path

RELATIVE = Path("openvpn/mbedtls/ssl/sslctx.hpp")
PIN = "fc4f42e03a3d7ae1da1e0454fd962deef6fc2dfbf5153e016ae11c3b84265bbd"
ANCHOR = """                // client cert+key
"""
INSERT = """                else if (c.mode.is_client())
                {
                    // Mbed TLS 3.6.8 requires an explicit hostname decision.
                    // OpenVPN's verify_callback_client checks the configured
                    // exact certificate identity in addition to CA validation.
                    const auto mode = c.verify_x509_name.get_mode();
                    if (!c.ca_chain || (c.flags & SSLConst::NO_VERIFY_PEER)
                        || (mode != VerifyX509Name::VERIFY_X509_SUBJECT_DN
                            && mode != VerifyX509Name::VERIFY_X509_SUBJECT_RDN)
                        || c.verify_x509_name.verify(""))
                        throw MbedTLSException("Exact OpenVPN server identity required");
                    if (mbedtls_ssl_set_hostname(ssl, nullptr))
                        throw MbedTLSException("Explicit OpenVPN identity policy failed");
                }

"""


def prepare(source: Path, output: Path) -> Path:
    raw = (source / RELATIVE).read_bytes().replace(b"\r\n", b"\n")
    if hashlib.sha256(raw).hexdigest() != PIN:
        raise ValueError("OpenVPN TLS header does not match reviewed revision")
    header = raw.decode("utf-8")
    if header.count(ANCHOR) != 1:
        raise ValueError("Unexpected TLS header layout")
    target = output / RELATIVE
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(header.replace(ANCHOR, INSERT + ANCHOR, 1).encode("utf-8"))
    return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(prepare(args.source, args.output))
