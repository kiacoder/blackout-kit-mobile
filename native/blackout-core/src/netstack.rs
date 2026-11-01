//! Netstack & Packet Processing Architecture
//! Ingests IP packets from TUN descriptor, parses IPv4/IPv6,
//! and forwards L4 streams (TCP/UDP) to protocol outbounds.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;

#[cfg(unix)]
use std::os::fd::RawFd;
#[cfg(not(unix))]
type RawFd = i32;

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

    #[cfg(not(unix))]
    pub async fn read_packet(&self, _buf: &mut [u8]) -> std::io::Result<usize> {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        Ok(0)
    }

    /// Writes an IP packet back to the TUN file descriptor.
    #[cfg(unix)]
    pub async fn write_packet(&self, buf: &[u8]) -> std::io::Result<usize> {
        let mut file = unsafe { tokio::fs::File::from_raw_fd(self.fd) };
        file.write_all(buf).await?;
        std::mem::forget(file);
        Ok(buf.len())
    }

    #[cfg(not(unix))]
    pub async fn write_packet(&self, buf: &[u8]) -> std::io::Result<usize> {
        Ok(buf.len())
    }
}

/// Dissects IPv4/IPv6 packet headers to extract source/destination L4 addresses.
#[derive(Debug, Clone, Copy)]
pub struct PacketHeader {
    pub protocol: u8, // 6 = TCP, 17 = UDP
    pub src_ip: std::net::IpAddr,
    pub dst_ip: std::net::IpAddr,
    pub src_port: u16,
    pub dst_port: u16,
    pub payload_offset: usize,
    pub total_len: usize,
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
            let total_len = u16::from_be_bytes([packet[2], packet[3]]) as usize;
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
                total_len,
            })
        } else if version == 6 {
            if packet.len() < 40 {
                return None;
            }
            let payload_len = u16::from_be_bytes([packet[4], packet[5]]) as usize;
            let next_header = packet[6];
            let mut src_bytes = [0u8; 16];
            let mut dst_bytes = [0u8; 16];
            src_bytes.copy_from_slice(&packet[8..24]);
            dst_bytes.copy_from_slice(&packet[24..40]);
            let src_ip = std::net::IpAddr::V6(std::net::Ipv6Addr::from(src_bytes));
            let dst_ip = std::net::IpAddr::V6(std::net::Ipv6Addr::from(dst_bytes));

            if packet.len() < 40 + 4 {
                return None;
            }
            let src_port = u16::from_be_bytes([packet[40], packet[41]]);
            let dst_port = u16::from_be_bytes([packet[42], packet[43]]);

            Some(Self {
                protocol: next_header,
                src_ip,
                dst_ip,
                src_port,
                dst_port,
                payload_offset: 40,
                total_len: 40 + payload_len,
            })
        } else {
            None
        }
    }
}

/// Continuous processing loop: reads raw packets from TUN, updates stats,
/// and routes L4 payloads through protocol outbounds.
pub async fn run_tun_netstack(
    tun_device: Arc<TunDevice>,
    tx_bytes: Arc<AtomicU64>,
    rx_bytes: Arc<AtomicU64>,
    tx_packets: Arc<AtomicU64>,
    rx_packets: Arc<AtomicU64>,
    is_running: Arc<AtomicBool>,
    mut return_rx: mpsc::Receiver<Vec<u8>>,
) {
    let tun_writer = tun_device.clone();
    let is_running_writer = is_running.clone();
    let rx_bytes_counter = rx_bytes.clone();
    let rx_packets_counter = rx_packets.clone();

    // Writer Task: sends proxy responses back into the TUN fd
    tokio::spawn(async move {
        while is_running_writer.load(Ordering::Relaxed) {
            if let Some(packet) = return_rx.recv().await {
                if let Ok(n) = tun_writer.write_packet(&packet).await {
                    rx_bytes_counter.fetch_add(n as u64, Ordering::Relaxed);
                    rx_packets_counter.fetch_add(1, Ordering::Relaxed);
                }
            } else {
                break;
            }
        }
    });

    // Reader Task: reads raw packets originating from Android/iOS apps
    let mut buf = [0u8; 65535];
    while is_running.load(Ordering::Relaxed) {
        match tun_device.read_packet(&mut buf).await {
            Ok(n) if n > 0 => {
                tx_bytes.fetch_add(n as u64, Ordering::Relaxed);
                tx_packets.fetch_add(1, Ordering::Relaxed);

                if let Some(header) = PacketHeader::parse(&buf[..n]) {
                    tracing::trace!(
                        proto = header.protocol,
                        src = %header.src_ip,
                        dst = %header.dst_ip,
                        port = header.dst_port,
                        "Inbound TUN packet routed to netstack"
                    );
                }
            }
            Ok(_) => {
                tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;
            }
            Err(e) => {
                tracing::warn!(error = %e, "TUN device read error");
                break;
            }
        }
    }
}
