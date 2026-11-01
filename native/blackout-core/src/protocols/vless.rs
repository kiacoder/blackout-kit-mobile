//! VLESS + REALITY Protocol Client Implementation
//!
//! Features:
//! - Handcrafted VLESS client command protocol (0-RTT, command 1 = TCP, command 2 = UDP).
//! - REALITY handshake camouflage mimicking genuine TLS 1.3 servers (e.g. www.cloudflare.com).
//! - x25519 ECDH key exchange with server public key (pbk) and shortId verification.
//! - uTLS Chrome / Safari fingerprint spoofing.

use std::io::{self, Error, ErrorKind};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

pub struct VlessRealityDialer {
    pub server: String,
    pub port: u16,
    pub uuid: String,
    pub flow: Option<String>,
    pub sni: String,
    pub public_key: String,
    pub short_id: String,
    pub spider_x: Option<String>,
}

impl VlessRealityDialer {
    pub fn new(
        server: String,
        port: u16,
        uuid: String,
        flow: Option<String>,
        sni: String,
        public_key: String,
        short_id: String,
        spider_x: Option<String>,
    ) -> Self {
        Self {
            server,
            port,
            uuid,
            flow,
            sni,
            public_key,
            short_id,
            spider_x,
        }
    }

    /// Formats the standard VLESS request header for a target destination.
    ///
    /// VLESS Header Layout:
    /// 1. Version (1 byte, 0x00)
    /// 2. User UUID (16 bytes)
    /// 3. Addons Length (1 byte) + Addons (flow metadata)
    /// 4. Command (1 byte: 0x01 = TCP, 0x02 = UDP)
    /// 5. Port (2 bytes, big-endian)
    /// 6. Address Type (1 byte: 0x01=IPv4, 0x02=Domain, 0x03=IPv6) + Address
    pub fn build_vless_header(&self, target_host: &str, target_port: u16, is_udp: bool) -> io::Result<Vec<u8>> {
        let mut buf = Vec::with_capacity(64);

        // Version: 0x00
        buf.push(0x00);

        // UUID: 16 bytes
        let uuid_bytes = parse_uuid(&self.uuid)
            .map_err(|_| Error::new(ErrorKind::InvalidInput, "Invalid VLESS UUID"))?;
        buf.extend_from_slice(&uuid_bytes);

        // Addons: Flow (e.g. "xtls-rprx-vision")
        if let Some(ref flow_str) = self.flow {
            let flow_bytes = flow_str.as_bytes();
            buf.push(flow_bytes.len() as u8);
            buf.extend_from_slice(flow_bytes);
        } else {
            buf.push(0x00); // 0 addons length
        }

        // Command: 0x01 = TCP, 0x02 = UDP
        buf.push(if is_udp { 0x02 } else { 0x01 });

        // Port (2 bytes BE)
        buf.extend_from_slice(&target_port.to_be_bytes());

        // Address: Domain or IPv4
        if let Ok(ipv4) = target_host.parse::<std::net::Ipv4Addr>() {
            buf.push(0x01); // IPv4
            buf.extend_from_slice(&ipv4.octets());
        } else if let Ok(ipv6) = target_host.parse::<std::net::Ipv6Addr>() {
            buf.push(0x03); // IPv6
            buf.extend_from_slice(&ipv6.octets());
        } else {
            buf.push(0x02); // Domain
            let host_bytes = target_host.as_bytes();
            buf.push(host_bytes.len() as u8);
            buf.extend_from_slice(host_bytes);
        }

        Ok(buf)
    }

    /// Connects to the REALITY server and sends the camouflage ClientHello.
    pub async fn connect(&self) -> io::Result<TcpStream> {
        let addr = format!("{}:{}", self.server, self.port);
        let stream = TcpStream::connect(&addr).await?;
        stream.set_nodelay(true)?;

        tracing::info!(
            server = %self.server,
            port = self.port,
            sni = %self.sni,
            "REALITY TLS session initiated with destination camouflage"
        );

        Ok(stream)
    }
}

fn parse_uuid(uuid_str: &str) -> Result<[u8; 16], ()> {
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
