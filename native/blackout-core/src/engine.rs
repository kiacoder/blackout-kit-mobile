//! Native Engine Session Runner & Outbound Dispatcher
//! Manages active tunnel loop, TUN read/write routines, and protocol outbound switching.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot};

use crate::config::{EngineConfig, OutboundConfig};
use crate::netstack::{run_tun_netstack, TunDevice};
use crate::EngineStats;

pub struct EngineSession {
    pub tun_fd: i32,
    pub config: EngineConfig,
    pub stats: Arc<EngineStats>,
    pub is_running: Arc<AtomicBool>,
}

impl EngineSession {
    pub fn new(
        tun_fd: i32,
        config: EngineConfig,
        stats: Arc<EngineStats>,
        is_running: Arc<AtomicBool>,
    ) -> Self {
        Self {
            tun_fd,
            config,
            stats,
            is_running,
        }
    }

    /// Spawns the async tunnel loop.
    pub async fn run(self, mut shutdown_rx: oneshot::Receiver<()>) {
        tracing::info!(tun_fd = self.tun_fd, "Engine session loop starting");

        match self.config.outbound {
            OutboundConfig::Vless { server, server_port, uuid, flow, sni, public_key, short_id, spider_x, .. } => {
                let dialer = crate::protocols::vless::VlessRealityDialer::new(
                    server,
                    server_port,
                    uuid,
                    flow,
                    sni.unwrap_or_default(),
                    public_key.unwrap_or_default(),
                    short_id.unwrap_or_default(),
                    spider_x,
                );
                tracing::info!("Dispatched VLESS REALITY outbound: {}:{}", dialer.server, dialer.port);
            }
            OutboundConfig::Shadowsocks { server, server_port, method, password } => {
                let dialer = crate::protocols::shadowsocks2022::Shadowsocks2022Dialer::new(
                    server,
                    server_port,
                    method,
                    &password,
                );
                tracing::info!("Dispatched Shadowsocks-2022 outbound: {}:{}", dialer.server, dialer.port);
            }
            OutboundConfig::ShadowTls { server, server_port, password, sni, version } => {
                let dialer = crate::protocols::shadowtls::ShadowTlsDialer::new(
                    server,
                    server_port,
                    password,
                    sni.unwrap_or_default(),
                    version,
                );
                tracing::info!("Dispatched ShadowTLS v{} outbound: {}:{}", dialer.version, dialer.server, dialer.port);
            }
            OutboundConfig::Hysteria2 { server, server_port, password, sni, insecure, hop_ports, up_mbps, down_mbps } => {
                let dialer = crate::protocols::hysteria2::Hysteria2Dialer::new(
                    server,
                    server_port,
                    password,
                    sni,
                    insecure,
                    hop_ports.as_deref(),
                    up_mbps,
                    down_mbps,
                );
                tracing::info!("Dispatched Hysteria 2 outbound: {}:{}", dialer.server, dialer.port);
            }
            OutboundConfig::Tuic { server, server_port, uuid, password, sni, insecure, congestion_control } => {
                let dialer = crate::protocols::tuic::TuicDialer::new(
                    server,
                    server_port,
                    uuid,
                    password,
                    sni,
                    insecure,
                    congestion_control,
                );
                tracing::info!("Dispatched TUIC v5 outbound: {}:{}", dialer.server, dialer.port);
            }
            OutboundConfig::WireGuard { server, server_port, private_key, public_key, pre_shared_key, local_address, mtu } => {
                let dialer = crate::protocols::wireguard::WireGuardDialer::new_standard(
                    server,
                    server_port,
                    private_key,
                    public_key,
                    pre_shared_key,
                    local_address,
                    mtu,
                );
                tracing::info!("Dispatched WireGuard outbound: {}:{}", dialer.server, dialer.port);
            }
            OutboundConfig::AmneziaWg { server, server_port, private_key, public_key, pre_shared_key, local_address, mtu, jc, jmin, jmax, s1, s2, h1, h2, h3, h4 } => {
                let dialer = crate::protocols::wireguard::WireGuardDialer::new_amnezia(
                    server,
                    server_port,
                    private_key,
                    public_key,
                    pre_shared_key,
                    local_address,
                    mtu,
                    jc, jmin, jmax, s1, s2, h1, h2, h3, h4,
                );
                tracing::info!("Dispatched AmneziaWG obfuscated outbound: {}:{}", dialer.server, dialer.port);
            }
        }

        // Spawn TUN Netstack loop to process raw IP packets
        let (return_tx, return_rx) = mpsc::channel::<Vec<u8>>(1024);
        let tun_device = Arc::new(TunDevice::new(self.tun_fd));

        let netstack_future = run_tun_netstack(
            tun_device,
            self.stats.tx_bytes.clone(),
            self.stats.rx_bytes.clone(),
            self.stats.tx_packets.clone(),
            self.stats.rx_packets.clone(),
            self.is_running.clone(),
            return_rx,
        );

        tokio::select! {
            _ = netstack_future => {
                tracing::warn!("TUN netstack worker completed unexpectedly");
            }
            _ = &mut shutdown_rx => {
                tracing::info!("Shutdown signal received by engine session");
            }
        }

        self.is_running.store(false, Ordering::SeqCst);
        tracing::info!("Engine session loop shut down cleanly");
    }
}
