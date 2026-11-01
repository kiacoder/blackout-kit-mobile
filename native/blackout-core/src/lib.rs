pub mod config;
pub mod ffi;
pub mod netstack;
pub mod protocols;

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Default)]
pub struct EngineStats {
    pub tx_bytes: AtomicU64,
    pub rx_bytes: AtomicU64,
    pub tx_packets: AtomicU64,
    pub rx_packets: AtomicU64,
}

pub struct BlackoutEngine {
    is_running: Arc<AtomicBool>,
    stats: Arc<EngineStats>,
    shutdown_tx: Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>,
}

impl BlackoutEngine {
    pub fn new() -> Self {
        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            stats: Arc::new(EngineStats::default()),
            shutdown_tx: Arc::new(Mutex::new(None)),
        }
    }

    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }

    pub fn stats(&self) -> &EngineStats {
        &self.stats
    }
}
