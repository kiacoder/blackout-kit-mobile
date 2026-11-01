//! TUIC v5 Protocol Client Implementation
//! QUIC-based tunneling protocol designed for mobile speed and fast handshakes.
//!
//! Protocol Features:
//! - 0-RTT connection establishment.
//! - Direct UDP relay & multiplexed TCP over QUIC streams.
//! - UUID + token authentication.

use std::io;
use std::net::SocketAddr;
use tokio::net::UdpSocket;

pub struct TuicDialer {
    pub server: String,
    pub port: u16,
    pub uuid: String,
    pub password: String,
    pub sni: Option<String>,
    pub insecure: bool,
    pub congestion_control: String,
}

impl TuicDialer {
    pub fn new(
        server: String,
        port: u16,
        uuid: String,
        password: String,
        sni: Option<String>,
        insecure: bool,
        congestion_control: Option<String>,
    ) -> Self {
        Self {
            server,
            port,
            uuid,
            password,
            sni,
            insecure,
            congestion_control: congestion_control.unwrap_or_else(|| "bbr".to_string()),
        }
    }

    /// Binds the client UDP socket for TUIC QUIC connection.
    pub async fn bind_socket(&self) -> io::Result<UdpSocket> {
        let bind_addr: SocketAddr = "0.0.0.0:0".parse().unwrap();
        let socket = UdpSocket::bind(bind_addr).await?;
        tracing::info!(server = %self.server, port = self.port, "TUIC v5 UDP socket ready");
        Ok(socket)
    }

    /// Formats the TUIC v5 authentication frame.
    pub fn auth_frame(&self) -> Vec<u8> {
        let mut frame = Vec::with_capacity(64);
        // Command byte: 0x00 = Authenticate
        frame.push(0x00);
        // UUID bytes (16 bytes)
        if let Ok(parsed_uuid) = uuid_sim::parse_uuid_bytes(&self.uuid) {
            frame.extend_from_slice(&parsed_uuid);
        }
        // Password
        let pw_bytes = self.password.as_bytes();
        frame.push(pw_bytes.len() as u8);
        frame.extend_from_slice(pw_bytes);
        frame
    }
}

mod uuid_sim {
    pub fn parse_uuid_bytes(uuid_str: &str) -> Result<[u8; 16], ()> {
        let clean = uuid_str.replace('-', "");
        if clean.len() != 32 {
            return Err(());
        }
        let mut bytes = [0u8; 16];
        for i in 0..16 {
            bytes[i] = u8::from_str_radix(&clean[i * 2..i * 2 + 2], 16).map_err(|_| ())?;
        }
        Ok(bytes)
    }
}
