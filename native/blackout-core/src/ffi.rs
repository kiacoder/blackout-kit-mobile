use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, Once};
use tokio::runtime::Runtime;

use crate::{BlackoutEngine, EngineStats};

pub const BLACKOUT_OK: i32 = 0;
pub const BLACKOUT_ERR_INVALID_PARAM: i32 = -1;
pub const BLACKOUT_ERR_ALREADY_RUNNING: i32 = -2;
pub const BLACKOUT_ERR_NOT_RUNNING: i32 = -3;
pub const BLACKOUT_ERR_CONFIG_PARSE: i32 = -4;
pub const BLACKOUT_ERR_NETSTACK: i32 = -5;
pub const BLACKOUT_ERR_DIAL: i32 = -6;
pub const BLACKOUT_ERR_INTERNAL: i32 = -99;

#[repr(C)]
#[derive(Debug, Default, Clone, Copy)]
pub struct BlackoutStats {
    pub tx_bytes: u64,
    pub rx_bytes: u64,
    pub tx_packets: u64,
    pub rx_packets: u64,
    pub active_connections: u32,
}

static INIT_ONCE: Once = Once::new();
static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
static ENGINE: Mutex<Option<Arc<BlackoutEngine>>> = Mutex::new(None);
static LAST_ERROR: Mutex<String> = Mutex::new(String::new());

fn set_last_error(err: &str) {
    if let Ok(mut lock) = LAST_ERROR.lock() {
        *lock = err.to_string();
    }
}

#[no_mangle]
pub extern "C" fn blackout_init(log_level: i32) -> i32 {
    INIT_ONCE.call_once(|| {
        let filter = match log_level {
            0 => "error",
            1 => "warn",
            2 => "info",
            3 => "debug",
            _ => "trace",
        };
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .try_init();
    });

    let mut rt_lock = match RUNTIME.lock() {
        Ok(guard) => guard,
        Err(_) => return BLACKOUT_ERR_INTERNAL,
    };

    if rt_lock.is_none() {
        match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("blackout-core-worker")
            .build()
        {
            Ok(rt) => *rt_lock = Some(rt),
            Err(e) => {
                set_last_error(&format!("Failed to build Tokio runtime: {e}"));
                return BLACKOUT_ERR_INTERNAL;
            }
        }
    }

    BLACKOUT_OK
}

#[no_mangle]
pub extern "C" fn blackout_start(tun_fd: i32, config_json: *const c_char) -> i32 {
    if tun_fd < 0 || config_json.is_null() {
        set_last_error("Invalid file descriptor or config pointer");
        return BLACKOUT_ERR_INVALID_PARAM;
    }

    let config_str = unsafe {
        match CStr::from_ptr(config_json).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("Config string is not valid UTF-8");
                return BLACKOUT_ERR_CONFIG_PARSE;
            }
        }
    };

    let mut engine_lock = match ENGINE.lock() {
        Ok(guard) => guard,
        Err(_) => return BLACKOUT_ERR_INTERNAL,
    };

    if let Some(ref engine) = *engine_lock {
        if engine.is_running() {
            set_last_error("Engine is already active");
            return BLACKOUT_ERR_ALREADY_RUNNING;
        }
    }

    let engine = Arc::new(BlackoutEngine::new());
    engine.is_running.store(true, Ordering::SeqCst);
    *engine_lock = Some(engine);

    tracing::info!(tun_fd, "Blackout native core started");
    BLACKOUT_OK
}

#[no_mangle]
pub extern "C" fn blackout_stop() -> i32 {
    let mut engine_lock = match ENGINE.lock() {
        Ok(guard) => guard,
        Err(_) => return BLACKOUT_ERR_INTERNAL,
    };

    if let Some(engine) = engine_lock.take() {
        engine.is_running.store(false, Ordering::SeqCst);
        tracing::info!("Blackout native core stopped");
    }

    BLACKOUT_OK
}

#[no_mangle]
pub extern "C" fn blackout_is_running() -> bool {
    if let Ok(guard) = ENGINE.lock() {
        if let Some(ref engine) = *guard {
            return engine.is_running();
        }
    }
    false
}

#[no_mangle]
pub extern "C" fn blackout_get_stats(stats_out: *mut BlackoutStats) -> i32 {
    if stats_out.is_null() {
        return BLACKOUT_ERR_INVALID_PARAM;
    }

    if let Ok(guard) = ENGINE.lock() {
        if let Some(ref engine) = *guard {
            let s = engine.stats();
            unsafe {
                *stats_out = BlackoutStats {
                    tx_bytes: s.tx_bytes.load(Ordering::Relaxed),
                    rx_bytes: s.rx_bytes.load(Ordering::Relaxed),
                    tx_packets: s.tx_packets.load(Ordering::Relaxed),
                    rx_packets: s.rx_packets.load(Ordering::Relaxed),
                    active_connections: 0,
                };
            }
            return BLACKOUT_OK;
        }
    }

    unsafe {
        *stats_out = BlackoutStats::default();
    }
    BLACKOUT_OK
}

#[no_mangle]
pub extern "C" fn blackout_get_last_error(buffer: *mut c_char, max_len: i32) -> i32 {
    if buffer.is_null() || max_len <= 0 {
        return 0;
    }

    let err_str = match LAST_ERROR.lock() {
        Ok(guard) => guard.clone(),
        Err(_) => "Lock poisoned".to_string(),
    };

    let c_str = match CString::new(err_str) {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let bytes = c_str.as_bytes_with_nul();
    let to_copy = std::cmp::min(bytes.len(), max_len as usize);

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, buffer, to_copy);
        if to_copy > 0 {
            *buffer.add(to_copy - 1) = 0;
        }
    }

    to_copy as i32
}

#[no_mangle]
pub extern "C" fn blackout_version() -> *const c_char {
    static VERSION: &[u8] = b"BlackoutCore-Rust-0.1.0\0";
    VERSION.as_ptr() as *const c_char
}
