use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "protocol", rename_all = "lowercase")]
pub enum OutboundConfig {
    Vless {
        server: String,
        server_port: u16,
        uuid: String,
        flow: Option<String>,
        security: String,
        sni: Option<String>,
        public_key: Option<String>,
        short_id: Option<String>,
        spider_x: Option<String>,
    },
    Shadowsocks {
        server: String,
        server_port: u16,
        method: String,
        password: String,
    },
    Hysteria2 {
        server: String,
        server_port: u16,
        password: String,
        sni: Option<String>,
        insecure: bool,
        hop_ports: Option<String>,
        up_mbps: Option<u32>,
        down_mbps: Option<u32>,
    },
    Tuic {
        server: String,
        server_port: u16,
        uuid: String,
        password: String,
        sni: Option<String>,
        insecure: bool,
        congestion_control: Option<String>,
    },
    ShadowTls {
        server: String,
        server_port: u16,
        password: String,
        sni: Option<String>,
        version: u8,
    },
    WireGuard {
        server: String,
        server_port: u16,
        private_key: String,
        public_key: String,
        pre_shared_key: Option<String>,
        local_address: Vec<String>,
        mtu: Option<u16>,
    },
    AmneziaWg {
        server: String,
        server_port: u16,
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
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineConfig {
    pub outbound: OutboundConfig,
    #[serde(default = "default_dns")]
    pub dns_servers: Vec<String>,
    #[serde(default)]
    pub route_dns_through_proxy: bool,
}

fn default_dns() -> Vec<String> {
    vec!["1.1.1.1".to_string(), "1.0.0.1".to_string()]
}
