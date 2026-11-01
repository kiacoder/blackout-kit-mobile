//! Userspace Netstack: translates raw TUN IP packets into flows.
//!
//! Architecture:
//! - `TunDevice` owns the Android TUN file descriptor (raw packet I/O).
//! - `NetstackCore` terminates TCP properly via smoltcp (handshake,
//!   reassembly, ACKs, FIN/RST) — each app connection masquerades as the
//!   real destination. Relay data flows both directions:
//!   app → smoltcp socket → upstream pump → outbound (direct / VLESS).
//! - UDP is relayed via per-flow datagram sockets; responses are rebuilt
//!   as full IP/UDP packets (correct headers + checksums) and injected
//!   back into the TUN.
//! - Egress packets (handshake ACKs, FINs, relayed responses) travel the
//!   egress channel to the writer task, which writes them to the TUN fd.
//!
//! IPv6 is not relayed yet (v6-through-core needs a real v6 netstack);
//! v6 packets are counted and dropped, and apps fall back over v4.

mod device;
mod flows;
mod packet;

#[cfg(test)]
mod tests;

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

use smoltcp::iface::{Interface, SocketSet};
use smoltcp::socket::tcp::{Socket as TcpSocket, SocketBuffer, State as TcpState};
use smoltcp::wire::{HardwareAddress, IpAddress, IpCidr, Ipv4Address, Ipv6Address};
use tokio::sync::mpsc;

use crate::outbound::TcpOutbound;
use device::ChannelDevice;
use flows::{FlowKey, TcpFlow, UdpFlow, UpstreamMsg};

/// Must match VPN_MTU in BlackoutVpnService.kt.
const TUN_MTU: usize = 1400;
const TCP_MAX_FLOWS: usize = 256;
const UDP_MAX_FLOWS: usize = 256;
const TCP_SOCKET_BUFFER_BYTES: usize = 32 * 1024;
const UPSTREAM_CHANNEL_CAPACITY: usize = 64;
const EGRESS_CHANNEL_CAPACITY: usize = 4096;
/// Netstack servicing cadence. Fast enough for interactive traffic;
/// smoltcp timers (retransmits, delayed ACKs) tick between polls.
const TICK_MS: i64 = 10;
const UDP_IDLE_TIMEOUT_MS: i64 = 30_000;
/// Abort TCP flows that never completed their upstream dial.
const TCP_STALE_FLOW_MS: i64 = 120_000;
const CLEANUP_INTERVAL_MS: i64 = 1_000;
/// The TUN interface address configured by BlackoutVpnService.kt is
/// 10.111.222.1/30; the core masquerades from the sibling address.
const CORE_INTERFACE_ADDR: (u8, u8, u8, u8) = (10, 111, 222, 2);
const CORE_INTERFACE_PREFIX: u8 = 30;

pub struct TunDevice {
    pub fd: i32,
}

impl TunDevice {
    pub fn new(fd: i32) -> Self {
        Self { fd }
    }

    /// Reads an IP packet from the TUN file descriptor into the provided buffer.
    #[cfg(unix)]
    pub async fn read_packet(&self, buf: &mut [u8]) -> std::io::Result<usize> {
        use std::os::fd::FromRawFd;
        use tokio::io::AsyncReadExt;
        let mut file = unsafe { tokio::fs::File::from_raw_fd(self.fd) };
        let n = file.read(buf).await?;
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
        use std::os::fd::FromRawFd;
        use tokio::io::AsyncWriteExt;
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

fn to_smoltcp_ip(ip: std::net::IpAddr) -> IpAddress {
    match ip {
        std::net::IpAddr::V4(v4) => IpAddress::Ipv4(Ipv4Address(v4.octets())),
        std::net::IpAddr::V6(v6) => IpAddress::Ipv6(Ipv6Address(v6.octets())),
    }
}

/// The netstack state machine: owns the smoltcp interface, the flow tables
/// and all relay logic. Fully host-testable (no real fds involved).
pub struct NetstackCore {
    device: ChannelDevice,
    iface: Interface,
    sockets: SocketSet<'static>,
    tcp_flows: HashMap<FlowKey, TcpFlow>,
    udp_flows: HashMap<FlowKey, UdpFlow>,
    outbound: TcpOutbound,
    /// UDP relay is only safe when traffic is NOT proxied; with a proxy
    /// outbound, UDP would bypass the tunnel, so it is dropped instead.
    udp_relay_enabled: bool,
    started: std::time::Instant,
    last_cleanup_ms: i64,
}

impl NetstackCore {
    pub fn new(outbound: TcpOutbound, egress_tx: mpsc::Sender<Vec<u8>>) -> Self {
        let mut device = ChannelDevice::new(egress_tx, TUN_MTU);
        let mut config = smoltcp::iface::Config::new(HardwareAddress::Ip);
        config.random_seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos() as u64 ^ (d.as_secs() << 8))
            .unwrap_or(0xB1ACC07);
        let mut iface = Interface::new(
            config,
            &mut device,
            smoltcp::time::Instant::from_millis(0),
        );
        iface.set_any_ip(true);
        let (a, b, c, d) = CORE_INTERFACE_ADDR;
        iface.update_ip_addrs(|addrs| {
            addrs
                .push(IpCidr::new(
                    IpAddress::Ipv4(Ipv4Address([a, b, c, d])),
                    CORE_INTERFACE_PREFIX,
                ))
                .expect("core interface address slot");
        });
        let sockets = SocketSet::new(vec![]);
        let udp_relay_enabled = matches!(outbound, TcpOutbound::Direct);
        if !udp_relay_enabled {
            tracing::info!(
                outbound = %outbound.describe(),
                "UDP relay disabled: proxied UDP would bypass the tunnel"
            );
        }
        Self {
            device,
            iface,
            sockets,
            tcp_flows: HashMap::new(),
            udp_flows: HashMap::new(),
            outbound,
            udp_relay_enabled,
            started: std::time::Instant::now(),
            last_cleanup_ms: 0,
        }
    }

    fn now_ms(&self) -> i64 {
        self.started.elapsed().as_millis() as i64
    }

    /// Feeds one captured TUN packet into the netstack. UDP datagrams are
    /// relayed directly (they never enter smoltcp); TCP packets may create
    /// a masquerade listener before smoltcp consumes the SYN.
    pub async fn ingest(&mut self, packet: Vec<u8>) {
        if let Some(header) = packet::PacketHeader::parse(&packet) {
            if !header.src_ip.is_ipv4() {
                // IPv6 not relayed yet — dropped (counted by the driver).
                return;
            }
            match header.protocol {
                17 => {
                    if self.udp_relay_enabled {
                        self.handle_udp_datagram(&packet, &header).await;
                    } else {
                        tracing::debug!(
                            dst = %header.dst_ip,
                            port = header.dst_port,
                            "UDP dropped (proxied outbound)"
                        );
                    }
                    return;
                }
                6 => {
                    let key = FlowKey {
                        src: header.src_ip,
                        src_port: header.src_port,
                        dst: header.dst_ip,
                        dst_port: header.dst_port,
                    };
                    // Only a fresh SYN (no ACK) opens a flow; retransmits of
                    // an already-known tuple are handled by smoltcp itself.
                    let is_syn = header.tcp_flags(&packet) == Some(0x02);
                    if is_syn && !self.tcp_flows.contains_key(&key) {
                        self.create_tcp_listener(&key);
                    }
                }
                _ => return,
            }
        }
        self.device.ingress.push_back(packet);
    }

    /// One servicing step: poll smoltcp (consume ingress, emit egress),
    /// pump established TCP flows, pump UDP relay responses, and run the
    /// periodic cleanup.
    pub async fn tick(&mut self) {
        let now = smoltcp::time::Instant::from_millis(self.now_ms());
        let Self {
            iface,
            device,
            sockets,
            ..
        } = self;
        iface.poll(now, device, sockets);

        self.pump_tcp();
        self.pump_udp().await;

        let now_ms = self.now_ms();
        if now_ms - self.last_cleanup_ms >= CLEANUP_INTERVAL_MS {
            self.last_cleanup_ms = now_ms;
            self.cleanup(now_ms);
        }
    }

    fn create_tcp_listener(&mut self, key: &FlowKey) {
        if self.tcp_flows.len() >= TCP_MAX_FLOWS {
            tracing::warn!(
                target = %key.target(),
                "TCP flow table full; refusing new connection"
            );
            return;
        }
        let rx_buffer = SocketBuffer::new(vec![0u8; TCP_SOCKET_BUFFER_BYTES]);
        let tx_buffer = SocketBuffer::new(vec![0u8; TCP_SOCKET_BUFFER_BYTES]);
        let mut socket = TcpSocket::new(rx_buffer, tx_buffer);
        let listen_endpoint = (to_smoltcp_ip(key.dst), key.dst_port);
        if let Err(error) = socket.listen(listen_endpoint) {
            tracing::warn!(target = %key.target(), error = %error, "cannot listen on target endpoint");
            return;
        }
        let handle = self.sockets.add(socket);
        self.tcp_flows
            .insert(*key, TcpFlow::new(handle, self.now_ms()));
        tracing::debug!(target = %key.target(), "new TCP flow masquerading as target");
    }

    fn pump_tcp(&mut self) {
        let now_ms = self.now_ms();
        let keys: Vec<FlowKey> = self.tcp_flows.keys().copied().collect();
        for key in keys {
            let Some(flow) = self.tcp_flows.get_mut(&key) else {
                continue;
            };
            let handle = flow.handle;
            let socket = self.sockets.get_mut::<TcpSocket>(handle);

            // a) Handshake finished → dial upstream through the dispatcher.
            if !flow.connecting && socket.state() == TcpState::Established {
                flow.connecting = true;
                // Two channels: pump→netstack (upstream data) and
                // netstack→pump (app data). Both directions need capacity.
                let (to_netstack_tx, net_rx) =
                    mpsc::channel::<UpstreamMsg>(UPSTREAM_CHANNEL_CAPACITY);
                let (net_tx, to_pump_rx) =
                    mpsc::channel::<UpstreamMsg>(UPSTREAM_CHANNEL_CAPACITY);
                flow.up_tx = Some(net_tx);
                flow.up_rx = Some(net_rx);
                flows::spawn_upstream_pump(
                    self.outbound.clone(),
                    key.target(),
                    to_netstack_tx,
                    to_pump_rx,
                );
            }

            // b) Stale dial guard: never-established flows are torn down.
            if !flow.connecting && now_ms - flow.created_ms > TCP_STALE_FLOW_MS {
                tracing::warn!(target = %key.target(), "flow never established; aborting");
                socket.abort();
                flow.dead = true;
            }

            // c) Drain upstream messages into the pending queue.
            if let Some(up_rx) = flow.up_rx.as_mut() {
                while let Ok(msg) = up_rx.try_recv() {
                    match msg {
                        UpstreamMsg::Data(chunk) => {
                            flow.pending_to_socket.push_back(chunk);
                        }
                        UpstreamMsg::Eof => {
                            flow.upstream_eof_seen = true;
                        }
                        UpstreamMsg::DialFailed(reason) => {
                            tracing::info!(
                                target = %key.target(),
                                reason = %reason,
                                "refusing flow (outbound cannot dial)"
                            );
                            socket.abort();
                            flow.dead = true;
                            break;
                        }
                    }
                }
            }
            // d) Push pending upstream data into the smoltcp tx buffer.
            // MUST happen before the FIN gate below, or in-flight data
            // would be dropped when the upstream EOF arrives.
            while let Some(chunk) = flow.pending_to_socket.front_mut() {
                if !socket.can_send() {
                    break;
                }
                match socket.send_slice(chunk) {
                    Ok(0) => break, // tx buffer full
                    Ok(n) if n >= chunk.len() => {
                        flow.pending_to_socket.pop_front();
                    }
                    Ok(n) => {
                        chunk.drain(..n);
                        break;
                    }
                    Err(_) => {
                        socket.abort();
                        flow.dead = true;
                        break;
                    }
                }
            }
            if flow.upstream_eof_seen && socket.may_send() {
                // FIN toward the app once our tx buffer has drained (smoltcp
                // queues the FIN behind buffered data). Gated on may_send so
                // it fires exactly once per flow.
                socket.close();
            }

            // e) Move app data from the smoltcp rx buffer toward upstream.
            while socket.can_recv() && flow.pending_to_upstream.len() < 64 {
                let mut buf = [0u8; 16384];
                match socket.recv_slice(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        flow.pending_to_upstream.push_back(buf[..n].to_vec());
                    }
                    // Finished (peer FIN) or illegal: stop reading either way.
                    Err(_) => {
                        flow.peer_eof_seen = true;
                        break;
                    }
                }
            }
            if let Some(up_tx) = flow.up_tx.as_mut() {
                while let Some(chunk) = flow.pending_to_upstream.front() {
                    match up_tx.try_send(UpstreamMsg::Data(chunk.clone())) {
                        Ok(()) => {
                            flow.pending_to_upstream.pop_front();
                        }
                        Err(mpsc::error::TrySendError::Full(_)) => break,
                        Err(mpsc::error::TrySendError::Closed(_)) => {
                            flow.up_tx = None;
                            break;
                        }
                    }
                }
            }
            if flow.peer_eof_seen {
                // Dropping the sender closes the channel → the pump shuts
                // the upstream write half (FIN toward the server).
                flow.up_tx = None;
            }

            // f) Retire finished flows.
            let state = socket.state();
            if flow.dead || state == TcpState::Closed || state == TcpState::TimeWait {
                if flow.dead && state != TcpState::Closed {
                    socket.abort();
                }
                self.sockets.remove(handle);
                self.tcp_flows.remove(&key);
            }
        }
    }

    async fn handle_udp_datagram(&mut self, packet: &[u8], header: &packet::PacketHeader) {
        let Some(payload) = packet::udp_payload(packet, header) else {
            return;
        };
        if payload.len() > TUN_MTU.saturating_sub(28) {
            tracing::debug!(
                dst = %header.dst_ip,
                len = payload.len(),
                "UDP datagram exceeds TUN MTU; dropping"
            );
            return;
        }
        let key = FlowKey {
            src: header.src_ip,
            src_port: header.src_port,
            dst: header.dst_ip,
            dst_port: header.dst_port,
        };
        let now_ms = self.now_ms();
        if !self.udp_flows.contains_key(&key) {
            if self.udp_flows.len() >= UDP_MAX_FLOWS {
                self.evict_oldest_udp_flow();
            }
            match tokio::net::UdpSocket::bind("0.0.0.0:0").await {
                Ok(socket) => {
                    self.udp_flows.insert(
                        key,
                        UdpFlow {
                            socket,
                            last_active_ms: now_ms,
                        },
                    );
                }
                Err(error) => {
                    tracing::warn!(error = %error, "cannot bind UDP relay socket");
                    return;
                }
            }
        }
        let Some(flow) = self.udp_flows.get(&key) else {
            return;
        };
        let target = key.target();
        if let Err(error) = flow.socket.send_to(payload, target).await {
            tracing::warn!(target = %target, error = %error, "UDP relay send failed");
        }
    }

    async fn pump_udp(&mut self) {
        if !self.udp_relay_enabled || self.udp_flows.is_empty() {
            return;
        }
        let keys: Vec<FlowKey> = self.udp_flows.keys().copied().collect();
        let now_ms = self.now_ms();
        let ip_id = (now_ms & 0xffff) as u16;
        let mut buf = [0u8; 65536];
        for key in keys {
            let Some(flow) = self.udp_flows.get_mut(&key) else {
                continue;
            };
            flow.last_active_ms = now_ms;
            loop {
                match flow.socket.try_recv_from(&mut buf) {
                    Ok((n, _from)) => {
                        // Full-cone style rewrite: the response is rebuilt as
                        // if it came from the ORIGINAL destination so the
                        // app's conntrack accepts it.
                        let response = packet::build_udp_response_packet(
                            key.dst,
                            key.dst_port,
                            key.src,
                            key.src_port,
                            &buf[..n],
                            ip_id,
                        );
                        if response.is_empty() {
                            continue;
                        }
                        let _ = self.device.egress_tx.try_send(response);
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(error) => {
                        tracing::warn!(target = %key.target(), error = %error, "UDP relay socket error");
                        self.udp_flows.remove(&key);
                        break;
                    }
                }
            }
        }
    }

    fn evict_oldest_udp_flow(&mut self) {
        let oldest = self
            .udp_flows
            .iter()
            .min_by_key(|(_, flow)| flow.last_active_ms)
            .map(|(key, _)| *key);
        if let Some(key) = oldest {
            self.udp_flows.remove(&key);
        }
    }

    fn cleanup(&mut self, now_ms: i64) {
        // TCP: retire flows that finished or rotted.
        let stale_keys: Vec<FlowKey> = self
            .tcp_flows
            .iter()
            .filter(|(_, flow)| flow.quiesced() && now_ms - flow.created_ms > 5_000)
            .map(|(key, _)| *key)
            .collect();
        for key in stale_keys {
            if let Some(flow) = self.tcp_flows.remove(&key) {
                let socket = self.sockets.get_mut::<TcpSocket>(flow.handle);
                if socket.state() != TcpState::Closed {
                    socket.abort();
                }
                self.sockets.remove(flow.handle);
                tracing::debug!(target = %key.target(), "quiesced TCP flow retired");
            }
        }
        // UDP: drop idle flows.
        self.udp_flows
            .retain(|_, flow| now_ms - flow.last_active_ms <= UDP_IDLE_TIMEOUT_MS);
    }

    #[cfg(test)]
    pub(crate) fn tcp_flow_count(&self) -> usize {
        self.tcp_flows.len()
    }
}

/// Continuous netstack loop: reads raw packets from the TUN fd, feeds the
/// core, and writes egress packets back through the writer task.
pub async fn run_tun_netstack(
    tun_device: Arc<TunDevice>,
    tx_bytes: Arc<AtomicU64>,
    rx_bytes: Arc<AtomicU64>,
    tx_packets: Arc<AtomicU64>,
    rx_packets: Arc<AtomicU64>,
    is_running: Arc<AtomicBool>,
    outbound: TcpOutbound,
) {
    tracing::info!(outbound = %outbound.describe(), "netstack loop starting");

    // Writer task: sends proxy responses back into the TUN fd. This is the
    // return path — previously nothing ever fed it, so responses were lost.
    let (egress_tx, mut egress_rx) = mpsc::channel::<Vec<u8>>(EGRESS_CHANNEL_CAPACITY);
    {
        let tun_writer = tun_device.clone();
        let is_running_writer = is_running.clone();
        let rx_bytes_counter = rx_bytes.clone();
        let rx_packets_counter = rx_packets.clone();
        tokio::spawn(async move {
            while is_running_writer.load(Ordering::Relaxed) {
                match egress_rx.recv().await {
                    Some(packet) => {
                        if let Ok(n) = tun_writer.write_packet(&packet).await {
                            rx_bytes_counter.fetch_add(n as u64, Ordering::Relaxed);
                            rx_packets_counter.fetch_add(1, Ordering::Relaxed);
                        }
                    }
                    None => break,
                }
            }
            tracing::info!("netstack writer task exited");
        });
    }

    // Reader + core loop.
    let mut core = NetstackCore::new(outbound, egress_tx);
    let mut buf = vec![0u8; 65535];
    let mut ticker = tokio::time::interval(Duration::from_millis(TICK_MS as u64));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    while is_running.load(Ordering::Relaxed) {
        tokio::select! {
            _ = ticker.tick() => {
                core.tick().await;
            }
            read = tun_device.read_packet(&mut buf) => {
                match read {
                    Ok(n) if n > 0 => {
                        tx_bytes.fetch_add(n as u64, Ordering::Relaxed);
                        tx_packets.fetch_add(1, Ordering::Relaxed);
                        core.ingest(buf[..n].to_vec()).await;
                        core.tick().await;
                    }
                    Ok(_) => {
                        // Zero-length read: spurious wakeup, keep servicing.
                        core.tick().await;
                    }
                    Err(error) => {
                        tracing::warn!(error = %error, "TUN device read error");
                        break;
                    }
                }
            }
        }
    }

    tracing::info!("netstack loop exited");
}
