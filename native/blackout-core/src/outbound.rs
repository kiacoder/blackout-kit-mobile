//! Outbound Dispatcher: routes TCP flows from the netstack to either a
//! direct connection or a protocol dialer, based on the engine config.
//!
//! Safety policy: when the configured protocol's in-house dialer cannot yet
//! carry an end-to-end stream, flows are REFUSED (RST) instead of silently
//! dialed direct — a censorship-circumvention tool must never leak traffic
//! outside the tunnel it promised to build.

use std::io;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;

use crate::config::OutboundConfig;
use crate::protocols::vless::VlessRealityDialer;

/// Object-safe combined trait so the upstream stream can be boxed as a
/// single trait object (dyn only allows one non-auto trait).
pub trait AsyncReadWrite: AsyncRead + AsyncWrite + Unpin + Send {}

impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncReadWrite for T {}

/// Object-safe boxed stream handed to the per-flow upstream pump.
pub type UpstreamStream = Box<dyn AsyncReadWrite>;

/// TCP outbound dispatcher built from the engine's outbound config.
#[derive(Clone)]
pub enum TcpOutbound {
    /// Dial the original destination directly (measurement / plain VPN mode).
    Direct,
    /// VLESS over a plain TCP transport (`security: "none"`, no flow).
    Vless(Arc<VlessRealityDialer>),
    /// Protocol configured, but its in-house dialer cannot carry streams yet.
    Unsupported { protocol: &'static str, reason: String },
}

impl TcpOutbound {
    /// Short human-readable tag for logs.
    pub fn describe(&self) -> String {
        match self {
            TcpOutbound::Direct => "direct".to_string(),
            TcpOutbound::Vless(dialer) => {
                format!("vless (plain tcp) {}:{}", dialer.server, dialer.port)
            }
            TcpOutbound::Unsupported { protocol, .. } => format!("{protocol} (unsupported)"),
        }
    }

    /// Dials the target through this outbound and returns a stream positioned
    /// at the target's data (any proxy handshake preamble is consumed).
    pub async fn connect_tcp(&self, dst: SocketAddr) -> io::Result<UpstreamStream> {
        match self {
            TcpOutbound::Direct => {
                let stream = TcpStream::connect(dst).await?;
                stream.set_nodelay(true)?;
                Ok(Box::new(stream))
            }
            TcpOutbound::Vless(dialer) => {
                let mut stream = dialer.connect().await?;
                let header =
                    dialer.build_vless_header(&dst.ip().to_string(), dst.port(), false)?;
                stream.write_all(&header).await?;
                // VLESS response preamble: version (1 byte) + addons length
                // (1 byte) + addons. It must be consumed before target data
                // or the upstream stream misaligns by 2 + addons bytes.
                let mut preamble = [0u8; 2];
                stream.read_exact(&mut preamble).await?;
                let addons_len = preamble[1] as usize;
                if addons_len > 0 {
                    let mut addons = vec![0u8; addons_len];
                    stream.read_exact(&mut addons).await?;
                }
                Ok(Box::new(stream))
            }
            TcpOutbound::Unsupported { protocol, reason } => Err(io::Error::new(
                io::ErrorKind::Unsupported,
                format!(
                    "outbound protocol '{protocol}' cannot dial streams yet: {reason} \
                     (flows are refused instead of leaking outside the tunnel)"
                ),
            )),
        }
    }
}

/// Builds the TCP outbound from the engine config. Keeps the legacy
/// per-protocol selection logs so operators see which outbound was chosen.
pub fn build_outbound(config: &OutboundConfig) -> TcpOutbound {
    match config {
        OutboundConfig::Vless {
            server,
            server_port,
            uuid,
            flow,
            security,
            sni,
            public_key,
            short_id,
            spider_x,
        } => {
            let is_plain = security.eq_ignore_ascii_case("none") && flow.is_none();
            if is_plain {
                let dialer = Arc::new(VlessRealityDialer::new(
                    server.clone(),
                    *server_port,
                    uuid.clone(),
                    flow.clone(),
                    sni.clone().unwrap_or_default(),
                    public_key.clone().unwrap_or_default(),
                    short_id.clone().unwrap_or_default(),
                    spider_x.clone(),
                ));
                tracing::info!(
                    "Dispatched VLESS plain-TCP outbound: {}:{}",
                    dialer.server,
                    dialer.port
                );
                TcpOutbound::Vless(dialer)
            } else {
                tracing::warn!(
                    security = %security,
                    flow = flow.as_deref().unwrap_or("<none>"),
                    "VLESS REALITY/TLS transport is not implemented in the native core yet; flows will be refused"
                );
                TcpOutbound::Unsupported {
                    protocol: "vless",
                    reason: "REALITY/TLS transport handshake (uTLS + x25519) not implemented yet"
                        .to_string(),
                }
            }
        }
        OutboundConfig::Shadowsocks { server, server_port, method, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                method = %method,
                "Shadowsocks-2022 AEAD stream framing is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "shadowsocks-2022",
                reason: "2022-blake3 AEAD session framing not implemented yet".to_string(),
            }
        }
        OutboundConfig::ShadowTls { server, server_port, version, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                version,
                "ShadowTLS v3 handshake relay is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "shadowtls",
                reason: "v3 handshake relay not implemented yet".to_string(),
            }
        }
        OutboundConfig::Hysteria2 { server, server_port, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                "Hysteria 2 (QUIC via quinn) session dialer is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "hysteria2",
                reason: "QUIC (quinn) session dialer not implemented yet".to_string(),
            }
        }
        OutboundConfig::Tuic { server, server_port, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                "TUIC v5 (QUIC via quinn) session dialer is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "tuic",
                reason: "QUIC (quinn) session dialer not implemented yet".to_string(),
            }
        }
        OutboundConfig::WireGuard { server, server_port, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                "WireGuard userspace tunnel integration is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "wireguard",
                reason: "boringtun userspace tunnel integration not implemented yet".to_string(),
            }
        }
        OutboundConfig::AmneziaWg { server, server_port, .. } => {
            tracing::warn!(
                server = %server,
                port = server_port,
                "AmneziaWG userspace tunnel integration is not implemented in the native core yet; flows will be refused"
            );
            TcpOutbound::Unsupported {
                protocol: "amneziawg",
                reason: "boringtun userspace tunnel integration not implemented yet".to_string(),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn direct_outbound_dials_loopback() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut buf = [0u8; 5];
            use tokio::io::AsyncReadExt;
            sock.read_exact(&mut buf).await.unwrap();
        });
        let outbound = TcpOutbound::Direct;
        let mut stream = outbound.connect_tcp(addr).await.expect("dial must succeed");
        use tokio::io::AsyncWriteExt;
        stream.write_all(b"hello").await.unwrap();
    }

    #[tokio::test]
    async fn unsupported_outbound_returns_clear_error() {
        let outbound = TcpOutbound::Unsupported {
            protocol: "hysteria2",
            reason: "test".to_string(),
        };
        // Box<dyn AsyncReadWrite> has no Debug impl, so expect_err is out.
        let err = match outbound
            .connect_tcp("93.184.216.34:443".parse().unwrap())
            .await
        {
            Ok(_) => panic!("unsupported outbound must refuse to dial"),
            Err(e) => e,
        };
        assert_eq!(err.kind(), io::ErrorKind::Unsupported);
        assert!(err.to_string().contains("hysteria2"));
        assert!(err.to_string().contains("leaking"));
    }
}
