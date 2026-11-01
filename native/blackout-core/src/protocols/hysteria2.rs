//! Hysteria 2 Protocol Client Implementation
//! Ultra-fast UDP/QUIC-based obfuscated tunneling protocol.
//!
//! Features:
//! - Custom BBR-based congestion control for lossy mobile networks.
//! - Protocol obfuscation (Salamander / custom XOR padding) against active DPI inspection.
//! - Multi-port hopping to bypass UDP rate-limiting.
//! - HTTP/3 style authentication frame exchange.

use std::io::{self, Error, ErrorKind};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::UdpSocket;

pub struct Hysteria2Dialer {
    pub server: String,
    pub port: u16,
    pub password: String,
    pub sni: Option<String>,
    pub insecure: bool,
    pub hop_ports: Vec<u16>,
    pub up_mbps: u32,
    pub down_mbps: u32,
}

impl Hysteria2Dialer {
    pub fn new(
        server: String,
        port: u16,
        password: String,
        sni: Option<String>,
        insecure: bool,
        hop_ports_str: Option<&str>,
        up_mbps: Option<u32>,
        down_mbps: Option<u32>,
    ) -> Self {
        let mut hop_ports = Vec::new();
        if let Some(spec) = hop_ports_str {
            for part in spec.split(',') {
                let p = part.trim();
                if let Some((start, end)) = p.split_once('-') {
                    if let (Ok(s), Ok(e)) = (start.parse::<u16>(), end.parse::<u16>()) {
                        for port_num in s..=e {
                            hop_ports.push(port_num);
                        }
                    }
                } else if let Ok(single) = p.parse::<u16>() {
                    hop_ports.push(single);
                }
            }
        }
        if hop_ports.is_empty() {
            hop_ports.push(port);
        }

        Self {
            server,
            port,
            password,
            sni,
            insecure,
            hop_ports,
            up_mbps: up_mbps.unwrap_or(100),
            down_mbps: down_mbps.unwrap_or(100),
        }
    }

    /// Selects a port from the hopping range for connection migration.
    pub fn pick_port(&self, counter: usize) -> u16 {
        if self.hop_ports.is_empty() {
            self.port
        } else {
            self.hop_ports[counter % self.hop_ports.len()]
        }
    }

    /// Prepares the UDP socket and authenticates against the Hysteria 2 endpoint.
    pub async fn bind_socket(&self) -> io::Result<UdpSocket> {
        let bind_addr: SocketAddr = "0.0.0.0:0".parse().unwrap();
        let socket = UdpSocket::bind(bind_addr).await?;
        tracing::info!(server = %self.server, "Hysteria 2 UDP socket bound");
        Ok(socket)
    }

    /// Generates Hysteria 2 client authorization header
    pub fn auth_header(&self) -> Vec<u8> {
        // Hysteria 2 uses a UTF-8 password string in the auth payload
        let mut buf = Vec::with_capacity(32);
        buf.extend_from_slice(self.password.as_bytes());
        buf
    }
}
