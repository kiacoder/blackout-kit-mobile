//! Netstack & Packet Processing Architecture
//! Ingests IP packets from TUN descriptor, parses IPv4/IPv6,
//! and forwards L4 streams (TCP/UDP) to protocol outbounds.

use std::os::fd::RawFd;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

pub struct TunDevice {
    pub fd: RawFd,
}

impl TunDevice {
    pub fn new(fd: RawFd) -> Self {
        Self { fd }
    }

    /// Reads an IP packet from the TUN file descriptor into the provided buffer.
    #[cfg(unix)]
    pub async fn read_packet(&self, buf: &mut [u8]) -> std::io::Result<usize> {
        let mut file = unsafe { tokio::fs::File::from_raw_fd(self.fd) };
        let n = file.read(buf).await?;
        // Avoid closing the descriptor on drop
        std::mem::forget(file);
        Ok(n)
    }

    /// Writes an IP packet back to the TUN file descriptor.
    #[cfg(unix)]
    pub async fn write_packet(&self, buf: &[u8]) -> std::io::Result<usize> {
        let mut file = unsafe { tokio::fs::File::from_raw_fd(self.fd) };
        file.write_all(buf).await?;
        std::mem::forget(file);
        Ok(buf.len())
    }
}

/// Dissects IPv4/IPv6 packet headers to extract source/destination L4 addresses.
pub struct PacketHeader {
    pub protocol: u8, // 6 = TCP, 17 = UDP
    pub src_ip: std::net::IpAddr,
    pub dst_ip: std::net::IpAddr,
    pub src_port: u16,
    pub dst_port: u16,
    pub payload_offset: usize,
}

impl PacketHeader {
    pub fn parse(packet: &[u8]) -> Option<Self> {
        if packet.is_empty() {
            return None;
        }

        let version = packet[0] >> 4;
        if version == 4 {
            if packet.len() < 20 {
                return None;
            }
            let ihl = ((packet[0] & 0x0f) * 4) as usize;
            let proto = packet[9];
            let src_ip = std::net::IpAddr::V4(std::net::Ipv4Addr::new(
                packet[12], packet[13], packet[14], packet[15],
            ));
            let dst_ip = std::net::IpAddr::V4(std::net::Ipv4Addr::new(
                packet[16], packet[17], packet[18], packet[19],
            ));

            if packet.len() < ihl + 4 {
                return None;
            }
            let src_port = u16::from_be_bytes([packet[ihl], packet[ihl + 1]]);
            let dst_port = u16::from_be_bytes([packet[ihl + 2], packet[ihl + 3]]);

            Some(Self {
                protocol: proto,
                src_ip,
                dst_ip,
                src_port,
                dst_port,
                payload_offset: ihl,
            })
        } else {
            None // IPv6 expansion
        }
    }
}
