//! Android / JNI Bindings for BlackoutCoreEngine
#[cfg(target_os = "android")]
#[allow(non_snake_case)]
pub mod android {
    use crate::ffi::*;
    use jni::objects::{JClass, JString};
    use jni::sys::{jboolean, jint, jstring};
    use jni::JNIEnv;
    use std::ffi::CString;
    use std::os::raw::c_char;

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1init(
        _env: JNIEnv,
        _class: JClass,
        log_level: jint,
    ) -> jint {
        blackout_init(log_level)
    }

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1start(
        mut env: JNIEnv,
        _class: JClass,
        tun_fd: jint,
        config_json: JString,
    ) -> jint {
        let config_str: String = match env.get_string(&config_json) {
            Ok(s) => s.into(),
            Err(_) => return BLACKOUT_ERR_INVALID_PARAM,
        };
        let c_config = match CString::new(config_str) {
            Ok(c) => c,
            Err(_) => return BLACKOUT_ERR_CONFIG_PARSE,
        };
        blackout_start(tun_fd, c_config.as_ptr())
    }

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1stop(
        _env: JNIEnv,
        _class: JClass,
    ) -> jint {
        blackout_stop()
    }

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1is_1running(
        _env: JNIEnv,
        _class: JClass,
    ) -> jboolean {
        if blackout_is_running() { 1 } else { 0 }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1version(
        env: JNIEnv,
        _class: JClass,
    ) -> jstring {
        let ver = "BlackoutCore-Rust-0.1.0";
        match env.new_string(ver) {
            Ok(js) => js.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_com_blackoutkit_vpn_BlackoutCoreEngine_blackout_1get_1last_1error(
        mut env: JNIEnv,
        _class: JClass,
        buffer: jni::objects::JByteArray,
        max_len: jint,
    ) -> jint {
        if max_len <= 0 {
            return BLACKOUT_ERR_INVALID_PARAM;
        }

        let capacity = match env.get_array_length(&buffer) {
            Ok(length) => length,
            Err(_) => return BLACKOUT_ERR_INVALID_PARAM,
        };
        let bounded_len = max_len.min(capacity);
        if bounded_len <= 0 {
            return BLACKOUT_ERR_INVALID_PARAM;
        }

        let mut raw_buf = vec![0u8; bounded_len as usize];
        let copied = blackout_get_last_error(raw_buf.as_mut_ptr() as *mut c_char, bounded_len);
        if copied > 0 {
            let slice: &[i8] = unsafe { std::slice::from_raw_parts(raw_buf.as_ptr() as *const i8, copied as usize) };
            if env.set_byte_array_region(&buffer, 0, slice).is_err() {
                return BLACKOUT_ERR_INVALID_PARAM;
            }
        }
        copied
    }
}
