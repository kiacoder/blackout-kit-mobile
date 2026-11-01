//! Native Engine Session Runner & Outbound Dispatcher
//! Manages active tunnel loop, TUN read/write routines, and protocol outbound switching.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::oneshot;

use crate::config::EngineConfig;
use crate::netstack::TunDevice;
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

        // Build the outbound dispatcher from the config. Flows are routed
        // through it; unsupported protocols are refused (RST), never leaked.
        let outbound = crate::outbound::build_outbound(&self.config.outbound);

        // Spawn the TUN netstack. The core owns the egress channel; its
        // writer task injects every response packet back into the TUN fd.
        let tun_device = Arc::new(TunDevice::new(self.tun_fd));

        let netstack_future = crate::netstack::run_tun_netstack(
            tun_device,
            self.stats.tx_bytes.clone(),
            self.stats.rx_bytes.clone(),
            self.stats.tx_packets.clone(),
            self.stats.rx_packets.clone(),
            self.is_running.clone(),
            outbound,
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
