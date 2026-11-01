//! WireGuard & AmneziaWG User-space Engine
//!
//! Provides pure userspace WireGuard tunneling with optional AmneziaWG
//! header and junk packet obfuscation (Jc, Jmin, Jmax, S1, S2, H1-H4).

pub struct WireGuardDialer {
    pub server: String,
    pub port: u16,
    pub private_key: String,
    pub public_key: String,
    pub pre_shared_key: Option<String>,
    pub local_address: Vec<String>,
    pub mtu: u16,
    pub is_amnezia: bool,
    pub jc: u16,
    pub jmin: u16,
    pub jmax: u16,
    pub s1: u16,
    pub s2: u16,
    pub h1: u32,
    pub h2: u32,
    pub h3: u32,
    pub h4: u32,
}

impl WireGuardDialer {
    pub fn new_standard(
        server: String,
        port: u16,
        private_key: String,
        public_key: String,
        pre_shared_key: Option<String>,
        local_address: Vec<String>,
        mtu: Option<u16>,
    ) -> Self {
        Self {
            server,
            port,
            private_key,
            public_key,
            pre_shared_key,
            local_address,
            mtu: mtu.unwrap_or(1420),
            is_amnezia: false,
            jc: 0,
            jmin: 0,
            jmax: 0,
            s1: 0,
            s2: 0,
            h1: 0,
            h2: 0,
            h3: 0,
            h4: 0,
        }
    }

    pub fn new_amnezia(
        server: String,
        port: u16,
        private_key: String,
        public_key: String,
        pre_shared_key: Option<String>,
        local_address: Vec<String>,
        mtu: Option<u16>,
        jc: u16,
        jmin: u16,
        jmax: u16,
        s1: u16,
        s2: u16,
        h1: u32,
        h2: u32,
        h3: u32,
        h4: u32,
    ) -> Self {
        Self {
            server,
            port,
            private_key,
            public_key,
            pre_shared_key,
            local_address,
            mtu: mtu.unwrap_or(1420),
            is_amnezia: true,
            jc,
            jmin,
            jmax,
            s1,
            s2,
            h1,
            h2,
            h3,
            h4,
        }
    }
}
