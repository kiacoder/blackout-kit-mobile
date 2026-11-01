//! Packet parsing & synthesis for the userspace netstack.
//!
//! Inbound: dissects IPv4/IPv6 headers to extract L4 addresses and offsets.
//! Outbound: builds UDP/IP response packets so return traffic can be
//! injected back into the TUN with correct checksums.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// Dissects IPv4/IPv6 packet headers to extract source/destination L4 addresses.
#[derive(Debug, Clone, Copy)]
pub struct PacketHeader {
    pub protocol: u8, // 6 = TCP, 17 = UDP
    pub src_ip: IpAddr,
    pub dst_ip: IpAddr,
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
            if ihl < 20 || total_len < ihl || total_len > packet.len() {
                return None;
            }
            let fragment = u16::from_be_bytes([packet[6], packet[7]]);
            if fragment & 0x1fff != 0 {
                return None;
            }
            let proto = packet[9];
            if proto != 6 && proto != 17 {
                return None;
            }
            let src_ip = IpAddr::V4(Ipv4Addr::new(packet[12], packet[13], packet[14], packet[15]));
            let dst_ip = IpAddr::V4(Ipv4Addr::new(packet[16], packet[17], packet[18], packet[19]));

            if total_len < ihl + 4 || packet.len() < ihl + 4 {
                return None;
            }
            if proto == 6 && total_len < ihl + 20 {
                return None;
            }
            if proto == 17 && total_len < ihl + 8 {
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
            let total_len = 40 + payload_len;
            if total_len > packet.len() {
                return None;
            }
            let next_header = packet[6];
            if next_header != 6 && next_header != 17 {
                return None;
            }
            let mut src_bytes = [0u8; 16];
            let mut dst_bytes = [0u8; 16];
            src_bytes.copy_from_slice(&packet[8..24]);
            dst_bytes.copy_from_slice(&packet[24..40]);
            let src_ip = IpAddr::V6(Ipv6Addr::from(src_bytes));
            let dst_ip = IpAddr::V6(Ipv6Addr::from(dst_bytes));

            if (next_header == 6 && payload_len < 20)
                || (next_header == 17 && payload_len < 8)
                || packet.len() < 40 + 4
            {
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
                total_len,
            })
        } else {
            None
        }
    }

    /// Returns the TCP flags byte of the packet, if it is a valid TCP packet.
    pub fn tcp_flags<'p>(&self, packet: &'p [u8]) -> Option<u8> {
        if self.protocol != 6 || packet.len() < self.payload_offset + 14 {
            return None;
        }
        Some(packet[self.payload_offset + 13])
    }
}

/// Classic 16-bit ones' complement Internet checksum (RFC 1071).
pub fn internet_checksum(data: &[u8]) -> u16 {
    let mut sum: u32 = 0;
    let mut chunks = data.chunks_exact(2);
    for chunk in &mut chunks {
        sum += u16::from_be_bytes([chunk[0], chunk[1]]) as u32;
    }
    if let [odd] = chunks.remainder() {
        sum += ((*odd as u16) << 8) as u32;
    }
    // Fold carries until the high 16 bits are zero.
    while sum >> 16 != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    !(sum as u16)
}

/// Builds a complete UDP datagram packet (IP header + UDP header + payload)
/// to inject back into the TUN. `src` must be the ORIGINAL destination the
/// app talked to (we masquerade as it), `dst` is the app itself.
pub fn build_udp_response_packet(
    src_ip: IpAddr,
    src_port: u16,
    dst_ip: IpAddr,
    dst_port: u16,
    payload: &[u8],
    ip_id: u16,
) -> Vec<u8> {
    let udp_len = 8 + payload.len();
    match (src_ip, dst_ip) {
        (IpAddr::V4(src), IpAddr::V4(dst)) => {
            let total_len = 20 + udp_len;
            let mut out = Vec::with_capacity(total_len);
            // IPv4 header
            out.push(0x45); // version 4, IHL 5
            out.push(0x00); // DSCP/ECN
            out.extend_from_slice(&(total_len as u16).to_be_bytes());
            out.extend_from_slice(&ip_id.to_be_bytes());
            out.extend_from_slice(&0x4000u16.to_be_bytes()); // DF, no fragment offset
            out.push(64); // TTL
            out.push(17); // proto UDP
            out.extend_from_slice(&[0, 0]); // checksum placeholder
            out.extend_from_slice(&src.octets());
            out.extend_from_slice(&dst.octets());
            let checksum = internet_checksum(&out[..20]);
            out[10..12].copy_from_slice(&checksum.to_be_bytes());

            append_udp_header_and_payload(&mut out, src_ip, src_port, dst_ip, dst_port, payload);
            out
        }
        (IpAddr::V6(src), IpAddr::V6(dst)) => {
            let mut out = Vec::with_capacity(40 + udp_len);
            out.push(0x60); // version 6
            out.extend_from_slice(&[0, 0, 0]); // traffic class + flow label
            out.extend_from_slice(&(udp_len as u16).to_be_bytes());
            out.push(17); // next header UDP
            out.push(64); // hop limit
            out.extend_from_slice(&src.octets());
            out.extend_from_slice(&dst.octets());

            append_udp_header_and_payload(&mut out, src_ip, src_port, dst_ip, dst_port, payload);
            out
        }
        // Mixed-family responses are impossible for a real flow; refuse loudly.
        _ => Vec::new(),
    }
}

fn append_udp_header_and_payload(
    out: &mut Vec<u8>,
    src_ip: IpAddr,
    src_port: u16,
    dst_ip: IpAddr,
    dst_port: u16,
    payload: &[u8],
) {
    let udp_start = out.len();
    let udp_len = (8 + payload.len()) as u16;
    out.extend_from_slice(&src_port.to_be_bytes());
    out.extend_from_slice(&dst_port.to_be_bytes());
    out.extend_from_slice(&udp_len.to_be_bytes());
    out.extend_from_slice(&[0, 0]); // checksum placeholder

    // Pseudo-header for UDP checksum (same layout for v4/v6: src addr, dst
    // addr, zero byte, protocol, udp length).
    let mut pseudo = Vec::with_capacity(40 + 8 + payload.len());
    match (src_ip, dst_ip) {
        (IpAddr::V4(s), IpAddr::V4(d)) => {
            pseudo.extend_from_slice(&s.octets());
            pseudo.extend_from_slice(&d.octets());
        }
        (IpAddr::V6(s), IpAddr::V6(d)) => {
            pseudo.extend_from_slice(&s.octets());
            pseudo.extend_from_slice(&d.octets());
        }
        _ => {}
    }
    pseudo.extend_from_slice(&[0, 17]);
    pseudo.extend_from_slice(&udp_len.to_be_bytes());
    pseudo.extend_from_slice(&out[udp_start..udp_start + 8]);
    pseudo.extend_from_slice(payload);

    let checksum = internet_checksum(&pseudo);
    let checksum = if checksum == 0 { 0xffff } else { checksum };
    let csum_offset = udp_start + 6;
    out[csum_offset..csum_offset + 2].copy_from_slice(&checksum.to_be_bytes());

    out.extend_from_slice(payload);
}

/// Extracts the UDP data payload from a packet using the parsed header.
pub fn udp_payload<'p>(packet: &'p [u8], header: &PacketHeader) -> Option<&'p [u8]> {
    if header.protocol != 17 {
        return None;
    }
    let l4_start = header.payload_offset;
    if packet.len() < l4_start + 8 {
        return None;
    }
    let declared_udp_len = u16::from_be_bytes([packet[l4_start + 4], packet[l4_start + 5]]) as usize;
    if declared_udp_len < 8 {
        return None;
    }
    // Bound by both the IP total length and the declared UDP length.
    let ip_end = header.total_len.min(packet.len());
    let udp_end = (l4_start + declared_udp_len).min(ip_end);
    if udp_end <= l4_start + 8 {
        return None;
    }
    Some(&packet[l4_start + 8..udp_end])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ipv4_packet(total_len: u16, protocol: u8) -> [u8; 40] {
        let mut packet = [0u8; 40];
        packet[0] = 0x45;
        packet[2..4].copy_from_slice(&total_len.to_be_bytes());
        packet[9] = protocol;
        packet[12..16].copy_from_slice(&[10, 0, 0, 1]);
        packet[16..20].copy_from_slice(&[1, 1, 1, 1]);
        packet[20..22].copy_from_slice(&1234u16.to_be_bytes());
        packet[22..24].copy_from_slice(&443u16.to_be_bytes());
        packet
    }

    #[test]
    fn parses_valid_ipv4_tcp_header() {
        let packet = ipv4_packet(40, 6);
        let parsed = PacketHeader::parse(&packet).unwrap();
        assert_eq!(parsed.dst_port, 443);
        assert_eq!(parsed.protocol, 6);
        assert_eq!(parsed.total_len, 40);
    }

    #[test]
    fn rejects_invalid_ipv4_lengths_fragments_and_protocols() {
        assert!(PacketHeader::parse(&ipv4_packet(19, 6)).is_none());
        assert!(PacketHeader::parse(&ipv4_packet(25, 6)).is_none());

        let mut fragment = ipv4_packet(24, 6);
        fragment[6..8].copy_from_slice(&1u16.to_be_bytes());
        assert!(PacketHeader::parse(&fragment).is_none());

        assert!(PacketHeader::parse(&ipv4_packet(24, 1)).is_none());
    }

    #[test]
    fn rejects_ipv6_declared_length_overrun_and_extension_headers() {
        let mut packet = [0u8; 44];
        packet[0] = 0x60;
        packet[4..6].copy_from_slice(&8u16.to_be_bytes());
        packet[6] = 6;
        assert!(PacketHeader::parse(&packet).is_none());

        packet[4..6].copy_from_slice(&4u16.to_be_bytes());
        packet[6] = 0;
        assert!(PacketHeader::parse(&packet).is_none());
    }

    #[test]
    fn ipv4_header_checksum_self_validates() {
        // Build a header, compute its checksum, insert it, then verify the
        // RFC 1071 property: the checksum over the complete header is 0xffff.
        let mut header = vec![0u8; 20];
        header[0] = 0x45;
        header[2..4].copy_from_slice(&28u16.to_be_bytes());
        header[8] = 64;
        header[9] = 17;
        header[12..16].copy_from_slice(&[8, 8, 8, 8]);
        header[16..20].copy_from_slice(&[10, 0, 0, 5]);
        let csum = internet_checksum(&header);
        header[10..12].copy_from_slice(&csum.to_be_bytes());
        // RFC 1071: the ones'-complement checksum over the complete header
        // (checksum included) is 0.
        assert_eq!(internet_checksum(&header), 0);
    }

    #[test]
    fn udp_response_packet_round_trips_through_parser() {
        let src: IpAddr = "93.184.216.34".parse().unwrap();
        let dst: IpAddr = "10.0.0.5".parse().unwrap();
        let payload = b"pong-payload-\x01\x02\xff";
        let packet = build_udp_response_packet(src, 53, dst, 5555, payload, 0x1234);

        let header = PacketHeader::parse(&packet).expect("response must parse");
        assert_eq!(header.protocol, 17);
        assert_eq!(header.src_ip, src);
        assert_eq!(header.dst_ip, dst);
        assert_eq!(header.src_port, 53);
        assert_eq!(header.dst_port, 5555);
        assert_eq!(header.total_len, packet.len());
        assert_eq!(udp_payload(&packet, &header).unwrap(), payload);

        // IPv4 header checksum must self-validate.
        let mut full = packet.clone();
        full[10..12].copy_from_slice(&[0, 0]);
        let recomputed = internet_checksum(&full[..20]);
        assert_eq!(recomputed.to_be_bytes(), packet[10..12]);

        // UDP checksum (offset 20+6) must self-validate over pseudo-header.
        let mut udp_and_payload = packet[20..].to_vec();
        let mut pseudo = Vec::new();
        let src_bytes = match src {
            IpAddr::V4(s) => s.octets(),
            IpAddr::V6(_) => unreachable!(),
        };
        let dst_bytes = match dst {
            IpAddr::V4(d) => d.octets(),
            IpAddr::V6(_) => unreachable!(),
        };
        pseudo.extend_from_slice(&src_bytes);
        pseudo.extend_from_slice(&dst_bytes);
        pseudo.extend_from_slice(&[0, 17]);
        let udp_len = (8 + payload.len()) as u16;
        pseudo.extend_from_slice(&udp_len.to_be_bytes());
        udp_and_payload[6..8].copy_from_slice(&[0, 0]);
        pseudo.extend_from_slice(&udp_and_payload);
        let recomputed = internet_checksum(&pseudo);
        assert_eq!(recomputed.to_be_bytes(), packet[26..28]);
    }

    #[test]
    fn udp_response_packet_ipv6_round_trips() {
        let src: IpAddr = "2606:2800:220:1:248:1893:25c8:1946".parse().unwrap();
        let dst: IpAddr = "fd00::5".parse().unwrap();
        let payload = b"v6-pong";
        let packet = build_udp_response_packet(src, 443, dst, 5000, payload, 0);

        let header = PacketHeader::parse(&packet).expect("v6 response must parse");
        assert_eq!(header.protocol, 17);
        assert_eq!(header.src_ip, src);
        assert_eq!(header.dst_ip, dst);
        assert_eq!(udp_payload(&packet, &header).unwrap(), payload);
        assert_eq!(packet.len(), 40 + 8 + payload.len());
    }

    #[test]
    fn mixed_family_response_is_refused() {
        let packet = build_udp_response_packet(
            "1.2.3.4".parse().unwrap(),
            53,
            "fd00::5".parse().unwrap(),
            5000,
            b"x",
            0,
        );
        assert!(packet.is_empty());
    }

    #[test]
    fn udp_payload_bounds_respect_declared_length() {
        // Craft a UDP packet whose declared udp length is shorter than the
        // IP total length; payload extraction must honor the smaller bound.
        let mut packet = vec![0u8; 40];
        packet[0] = 0x45;
        packet[2..4].copy_from_slice(&40u16.to_be_bytes()); // IP total len
        packet[9] = 17;
        packet[12..16].copy_from_slice(&[10, 0, 0, 1]);
        packet[16..20].copy_from_slice(&[1, 1, 1, 1]);
        packet[20..22].copy_from_slice(&1000u16.to_be_bytes()); // sport
        packet[22..24].copy_from_slice(&53u16.to_be_bytes()); // dport
        packet[24..26].copy_from_slice(&12u16.to_be_bytes()); // udp len = 12 → 4 data bytes
        packet[28..32].copy_from_slice(b"data");
        packet[32..40].copy_from_slice(b"trailing"); // past declared udp len

        let header = PacketHeader::parse(&packet).unwrap();
        assert_eq!(udp_payload(&packet, &header).unwrap(), b"data");
    }
}
