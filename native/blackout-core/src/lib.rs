pub mod config;
pub mod engine;
pub mod ffi;
pub mod jni;
pub mod netstack;
pub mod protocols;

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct EngineStats {
    pub tx_bytes: Arc<AtomicU64>,
    pub rx_bytes: Arc<AtomicU64>,
    pub tx_packets: Arc<AtomicU64>,
    pub rx_packets: Arc<AtomicU64>,
}

impl Default for EngineStats {
    fn default() -> Self {
        Self {
            tx_bytes: Arc::new(AtomicU64::new(0)),
            rx_bytes: Arc::new(AtomicU64::new(0)),
            tx_packets: Arc::new(AtomicU64::new(0)),
            rx_packets: Arc::new(AtomicU64::new(0)),
        }
    }
}

pub struct BlackoutEngine {
    pub is_running: Arc<AtomicBool>,
    pub stats: Arc<EngineStats>,
    pub shutdown_tx: Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>,
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
