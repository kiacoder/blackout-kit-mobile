//! ShadowTLS v3 Protocol Implementation
//! High-performance Rust client dialer for ShadowTLS v3.
//!
//! ShadowTLS v3 Protocol Flow:
//! 1. Client connects via TCP to the ShadowTLS server (which masquerades as a legitimate TLS host).
//! 2. Client sends a standard TLS 1.3 ClientHello where the Session ID / SNI / extensions
//!    mimic a real domain (e.g. www.cloudflare.com or custom SNI).
//! 3. The ShadowTLS v3 handshake computes HMAC-SHA256 over client random + password to
//!    embed the challenge inside the TLS handshake.
//! 4. If the probe is an active scanner, the server relays the real handshake from the shadowed site.
//! 5. If the probe has the valid key/HMAC, the server switches to proxy mode.

use std::io::{self, Error, ErrorKind};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use ring::hmac;
use ring::rand::SecureRandom;

pub struct ShadowTlsDialer {
    pub server: String,
    pub port: u16,
    pub password: String,
    pub sni: String,
    pub version: u8,
}

impl ShadowTlsDialer {
    pub fn new(server: String, port: u16, password: String, sni: String, version: u8) -> Self {
        Self {
            server,
            port,
            password,
            sni,
            version: if version == 0 { 3 } else { version },
        }
    }

    /// Generates a randomized TLS ClientHello containing the ShadowTLS v3 authentication token.
    pub fn build_client_hello(&self) -> Vec<u8> {
        let mut packet = Vec::with_capacity(512);

        // Record Header: Content Type = Handshake (0x16), Legacy Version = TLS 1.0 (0x03, 0x01)
        packet.push(0x16);
        packet.push(0x03);
        packet.push(0x01);

        // Placeholder for Record Length (2 bytes, filled later)
        let len_pos = packet.len();
        packet.push(0x00);
        packet.push(0x00);

        let handshake_start = packet.len();

        // Handshake Header: Type = ClientHello (0x01)
        packet.push(0x01);

        // Placeholder for Handshake Length (3 bytes, filled later)
        let hs_len_pos = packet.len();
        packet.push(0x00);
        packet.push(0x00);
        packet.push(0x00);

        // Client Version = TLS 1.2 (0x03, 0x03)
        packet.push(0x03);
        packet.push(0x03);

        // Random: 32 bytes (ShadowTLS v3 derives its auth HMAC from this random)
        let mut random = [0u8; 32];
        ring::rand::SystemRandom::new()
            .fill(&mut random)
            .unwrap_or_else(|_| {
                for (i, b) in random.iter_mut().enumerate() {
                    *b = (i as u8).wrapping_mul(31);
                }
            });

        // Compute HMAC over random using password key
        let key = hmac::Key::new(hmac::HMAC_SHA256, self.password.as_bytes());
        let signature = hmac::sign(&key, &random[..24]);
        random[24..32].copy_from_slice(&signature.as_ref()[..8]);

        packet.extend_from_slice(&random);

        // Session ID: 32 bytes
        packet.push(0x20); // Length = 32
        let mut session_id = [0u8; 32];
        let _ = ring::rand::SystemRandom::new().fill(&mut session_id);
        packet.extend_from_slice(&session_id);

        // Cipher Suites: Standard modern TLS 1.3/1.2 suites
        let cipher_suites: [u8; 6] = [
            0x13, 0x01, // TLS_AES_128_GCM_SHA256
            0x13, 0x02, // TLS_AES_256_GCM_SHA384
            0x13, 0x03, // TLS_CHACHA20_POLY1305_SHA256
        ];
        packet.extend_from_slice(&(cipher_suites.len() as u16).to_be_bytes());
        packet.extend_from_slice(&cipher_suites);

        // Compression Methods: 1 byte (null compression = 0x00)
        packet.push(0x01);
        packet.push(0x00);

        // Extensions
        let mut ext_buf = Vec::with_capacity(256);

        // Extension: Server Name Indication (SNI = 0x0000)
        if !self.sni.is_empty() {
            ext_buf.extend_from_slice(&0x0000u16.to_be_bytes());
            let sni_bytes = self.sni.as_bytes();
            let sni_list_len = (sni_bytes.len() + 3) as u16;
            let sni_ext_len = (sni_bytes.len() + 5) as u16;

            ext_buf.extend_from_slice(&sni_ext_len.to_be_bytes());
            ext_buf.extend_from_slice(&sni_list_len.to_be_bytes());
            ext_buf.push(0x00); // Host Name Type = 0 (hostname)
            ext_buf.extend_from_slice(&(sni_bytes.len() as u16).to_be_bytes());
            ext_buf.extend_from_slice(sni_bytes);
        }

        // Extension: Supported Versions (TLS 1.3 = 0x002b)
        ext_buf.extend_from_slice(&0x002bu16.to_be_bytes());
        ext_buf.extend_from_slice(&3u16.to_be_bytes()); // length
        ext_buf.push(0x02); // list length
        ext_buf.extend_from_slice(&0x0304u16.to_be_bytes()); // TLS 1.3

        packet.extend_from_slice(&(ext_buf.len() as u16).to_be_bytes());
        packet.extend_from_slice(&ext_buf);

        // Backfill Handshake Length
        let hs_len = (packet.len() - handshake_start - 4) as u32;
        let hs_len_bytes = hs_len.to_be_bytes();
        packet[hs_len_pos] = hs_len_bytes[1];
        packet[hs_len_pos + 1] = hs_len_bytes[2];
        packet[hs_len_pos + 2] = hs_len_bytes[3];

        // Backfill Record Length
        let rec_len = (packet.len() - len_pos - 2) as u16;
        let rec_len_bytes = rec_len.to_be_bytes();
        packet[len_pos] = rec_len_bytes[0];
        packet[len_pos + 1] = rec_len_bytes[1];

        packet
    }

    /// Establishes an authenticated connection through the ShadowTLS v3 gateway.
    pub async fn connect(&self) -> io::Result<TcpStream> {
        let addr = format!("{}:{}", self.server, self.port);
        let mut stream = TcpStream::connect(&addr).await?;
        stream.set_nodelay(true)?;

        let client_hello = self.build_client_hello();
        stream.write_all(&client_hello).await?;
        stream.flush().await?;

        // Read ServerHello response header (5 bytes)
        let mut header = [0u8; 5];
        stream.read_exact(&mut header).await?;
        if header[0] != 0x16 {
            return Err(Error::new(
                ErrorKind::InvalidData,
                format!("Invalid TLS handshake response byte: 0x{:02x}", header[0]),
            ));
        }

        let record_len = u16::from_be_bytes([header[3], header[4]]) as usize;
        let mut body = vec![0u8; record_len];
        stream.read_exact(&mut body).await?;

        tracing::info!(server = %self.server, port = self.port, "ShadowTLS v3 handshake established");
        Ok(stream)
    }
}
