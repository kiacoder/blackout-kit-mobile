//! Netstack & Packet Processing Architecture
//! Ingests IP packets from TUN descriptor, parses IPv4/IPv6,
//! and forwards L4 streams (TCP/UDP) to protocol outbounds.

pub struct TunDevice {
    pub fd: i32,
}

impl TunDevice {
    pub fn new(fd: i32) -> Self {
        Self { fd }
    }
}
