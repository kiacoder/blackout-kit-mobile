//! Host integration tests: exercise the netstack end-to-end without any
//! real TUN fd. A second smoltcp interface plays the "Android app" side,
//! channel-paired with the netstack core; the upstream is a real loopback
//! TCP/UDP echo served by the test runtime.

use std::collections::VecDeque;
use std::net::{IpAddr, Ipv4Addr};

use smoltcp::iface::{Config as IfaceConfig, Interface, SocketSet};
use smoltcp::socket::tcp::{Socket as TcpSocket, SocketBuffer, State as TcpState};
use smoltcp::wire::{HardwareAddress, IpAddress, IpCidr, Ipv4Address};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use super::packet::{internet_checksum, PacketHeader};
use super::{NetstackCore, TICK_MS};
use crate::outbound::TcpOutbound;

/// App-side smoltcp device: its egress feeds the netstack's ingress and
/// vice versa (wired by the Harness drive loop below).
struct ClientDevice {
    ingress: VecDeque<Vec<u8>>,
    egress: VecDeque<Vec<u8>>,
}

impl smoltcp::phy::Device for ClientDevice {
    type RxToken<'a> = ClientRxToken;
    type TxToken<'a> = ClientTxToken<'a>;

    fn receive(
        &mut self,
        _timestamp: smoltcp::time::Instant,
    ) -> Option<(Self::RxToken<'_>, Self::TxToken<'_>)> {
        let packet = self.ingress.pop_front()?;
        Some((ClientRxToken(packet), ClientTxToken(&mut self.egress)))
    }

    fn transmit(&mut self, _timestamp: smoltcp::time::Instant) -> Option<Self::TxToken<'_>> {
        Some(ClientTxToken(&mut self.egress))
    }

    fn capabilities(&self) -> smoltcp::phy::DeviceCapabilities {
        let mut caps = smoltcp::phy::DeviceCapabilities::default();
        caps.medium = smoltcp::phy::Medium::Ip;
        caps.max_transmission_unit = 1400;
        caps
    }
}

struct ClientRxToken(Vec<u8>);

impl smoltcp::phy::RxToken for ClientRxToken {
    fn consume<R, F>(self, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut packet = self.0;
        f(&mut packet)
    }
}

struct ClientTxToken<'a>(&'a mut VecDeque<Vec<u8>>);

impl smoltcp::phy::TxToken for ClientTxToken<'_> {
    fn consume<R, F>(self, len: usize, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut buf = vec![0u8; len];
        let result = f(&mut buf);
        self.0.push_back(buf);
        result
    }
}

/// Drives the netstack core and a client-side smoltcp interface against
/// each other over in-memory packet queues.
struct Harness {
    core: NetstackCore,
    egress_rx: tokio::sync::mpsc::Receiver<Vec<u8>>,
    client_iface: Interface,
    client_sockets: SocketSet<'static>,
    client_device: ClientDevice,
    /// Test-visible copy of every packet the netstack emitted toward the
    /// "app" (the client iface consumes its own ingress queue during poll,
    /// dropping packets it has no socket for — e.g. relayed UDP responses).
    app_ingress: VecDeque<Vec<u8>>,
    round: i64,
}

const CLIENT_ADDR: Ipv4Addr = Ipv4Addr::new(10, 0, 0, 5);

static TRACING: std::sync::Once = std::sync::Once::new();

/// Enable tracing output during tests (RUST_LOG=debug cargo test ...).
fn init_tracing() {
    TRACING.call_once(|| {
        let _ = tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .try_init();
    });
}

impl Harness {
    fn new(core: NetstackCore, egress_rx: tokio::sync::mpsc::Receiver<Vec<u8>>) -> Self {
        let mut client_device = ClientDevice {
            ingress: VecDeque::new(),
            egress: VecDeque::new(),
        };
        let mut config = IfaceConfig::new(HardwareAddress::Ip);
        config.random_seed = 42;
        let mut client_iface = Interface::new(
            config,
            &mut client_device,
            smoltcp::time::Instant::from_millis(0),
        );
        client_iface.update_ip_addrs(|addrs| {
            addrs
                .push(IpCidr::new(
                    IpAddress::Ipv4(Ipv4Address(CLIENT_ADDR.octets())),
                    24,
                ))
                .expect("client addr slot");
        });
        let client_sockets = SocketSet::new(vec![]);
        Self {
            core,
            egress_rx,
            client_iface,
            client_sockets,
            client_device,
            app_ingress: VecDeque::new(),
            round: 0,
        }
    }

    async fn drive(&mut self) {
        self.round += 1;
        let now = smoltcp::time::Instant::from_millis(self.round * TICK_MS);

        // Client-emitted packets → netstack ingress.
        while let Some(pkt) = self.client_device.egress.pop_front() {
            self.core.ingest(pkt).await;
        }
        // Netstack servicing step.
        self.core.tick().await;
        // Netstack egress → client ingress (plus a test-visible copy).
        while let Ok(pkt) = self.egress_rx.try_recv() {
            self.app_ingress.push_back(pkt.clone());
            self.client_device.ingress.push_back(pkt);
        }
        // Client servicing step.
        self.client_iface
            .poll(now, &mut self.client_device, &mut self.client_sockets);
    }

    async fn drive_until(
        &mut self,
        mut condition: impl FnMut(&mut Harness) -> bool,
        max_rounds: usize,
        what: &str,
    ) {
        for _ in 0..max_rounds {
            self.drive().await;
            tokio::time::sleep(std::time::Duration::from_millis(1)).await;
            if condition(self) {
                return;
            }
        }
        panic!("harness timeout waiting for: {what}");
    }
}

fn app_client_socket() -> TcpSocket<'static> {
    let rx = SocketBuffer::new(vec![0u8; 16 * 1024]);
    let tx = SocketBuffer::new(vec![0u8; 16 * 1024]);
    TcpSocket::new(rx, tx)
}

async fn spawn_tcp_echo() -> std::net::SocketAddr {
    // Returning the addr requires capturing it before spawning; use a oneshot.
    let (tx, rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        let listener = match tokio::net::TcpListener::bind("127.0.0.1:0").await {
            Ok(l) => l,
            Err(_) => return,
        };
        let _ = tx.send(listener.local_addr().unwrap());
        loop {
            let Ok((mut sock, _)) = listener.accept().await else {
                return;
            };
            tokio::spawn(async move {
                let mut buf = [0u8; 4096];
                loop {
                    match sock.read(&mut buf).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            if sock.write_all(&buf[..n]).await.is_err() {
                                break;
                            }
                        }
                    }
                }
            });
        }
    });
    rx.await.expect("echo server did not bind")
}

fn drain_client_socket(harness: &mut Harness, handle: smoltcp::iface::SocketHandle) -> Vec<u8> {
    let socket = harness.client_sockets.get_mut::<TcpSocket>(handle);
    let mut received = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        match socket.recv_slice(&mut buf) {
            Ok(0) => break,
            Ok(n) => received.extend_from_slice(&buf[..n]),
            Err(_) => break,
        }
    }
    received
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tcp_echo_flows_bidirectionally_through_netstack() {
    let echo_addr = spawn_tcp_echo().await;
    let echo_ip = match echo_addr.ip() {
        IpAddr::V4(v4) => v4,
        other => panic!("unexpected echo server family: {other}"),
    };

    let (egress_tx, egress_rx) = tokio::sync::mpsc::channel(4096);
    let core = NetstackCore::new(TcpOutbound::Direct, egress_tx);
    let mut harness = Harness::new(core, egress_rx);

    // The "app" opens a connection to the echo server THROUGH the netstack.
    let handle = harness.client_sockets.add(app_client_socket());
    let remote = (IpAddress::Ipv4(Ipv4Address(echo_ip.octets())), echo_addr.port());
    let local = (IpAddress::Ipv4(Ipv4Address(CLIENT_ADDR.octets())), 40000u16);
    {
        let cx = harness.client_iface.context();
        harness
            .client_sockets
            .get_mut::<TcpSocket>(handle)
            .connect(cx, remote, local)
            .expect("client connect");
    }

    // Handshake completes; the netstack then dials the real loopback echo.
    harness
        .drive_until(
            |h| h.client_sockets.get::<TcpSocket>(handle).state() == TcpState::Established,
            400,
            "client handshake established",
        )
        .await;

    // App sends data; the echo must come back through the whole pipeline:
    // client → netstack socket → pump → loopback echo → pump → netstack → app.
    const PAYLOAD: &[u8] = b"hello blackout core, round trip me";
    {
        let socket = harness.client_sockets.get_mut::<TcpSocket>(handle);
        socket.send_slice(PAYLOAD).expect("client send");
    }

    harness
        .drive_until(
            |h| drain_client_socket(h, handle).len() >= PAYLOAD.len(),
            600,
            "echo payload received by app",
        )
        .await;

    // App closes; the FIN must propagate and the flow must retire.
    {
        let socket = harness.client_sockets.get_mut::<TcpSocket>(handle);
        socket.close();
    }
    harness
        .drive_until(
            |h| h.core.tcp_flow_count() == 0,
            400,
            "flow retirement after close",
        )
        .await;
    assert_eq!(harness.core.tcp_flow_count(), 0, "flow must retire after close");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn udp_relay_injects_wellformed_response_packets() {
    init_tracing();
    // UDP echo "server" = the "DNS server". Owned by the test (not spawned)
    // so the test can verify exactly one request/reply exchange.
    let echo = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let echo_addr = echo.local_addr().unwrap();
    let echo_ip = match echo_addr.ip() {
        IpAddr::V4(v4) => v4,
        other => panic!("unexpected echo server family: {other}"),
    };

    let (egress_tx, egress_rx) = tokio::sync::mpsc::channel(4096);
    let core = NetstackCore::new(TcpOutbound::Direct, egress_tx);
    let mut harness = Harness::new(core, egress_rx);

    // Craft an app→server UDP datagram as it would arrive on the TUN.
    let app_port = 5555u16;
    let payload = b"blackout-udp-probe";
    let mut datagram = Vec::new();
    datagram.push(0x45);
    datagram.extend_from_slice(&[0]); // TOS (1 byte)
    let total_len = (20 + 8 + payload.len()) as u16;
    datagram.extend_from_slice(&total_len.to_be_bytes());
    datagram.extend_from_slice(&[0, 0, 0, 0]); // id + flags
    datagram.push(64);
    datagram.push(17);
    datagram.extend_from_slice(&[0, 0]); // header checksum zeroed on purpose
    datagram.extend_from_slice(&CLIENT_ADDR.octets());
    datagram.extend_from_slice(&echo_ip.octets());
    datagram.extend_from_slice(&app_port.to_be_bytes());
    datagram.extend_from_slice(&echo_addr.port().to_be_bytes());
    datagram.extend_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
    datagram.extend_from_slice(&[0, 0]); // udp checksum zeroed
    datagram.extend_from_slice(payload);

    harness.core.ingest(datagram).await;
    harness.drive().await;

    // The relay socket must have forwarded the payload to the echo server.
    let mut rx_buf = [0u8; 2048];
    let (n, relay_from) = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        echo.recv_from(&mut rx_buf),
    )
    .await
    .expect("echo must receive within timeout")
    .expect("echo recv");
    assert_eq!(&rx_buf[..n], payload);
    assert_eq!(n, payload.len());

    // The echo replies to the relay socket; the netstack must rebuild it as
    // a full IP packet masquerading as the original destination.
    echo.send_to(payload, relay_from).await.unwrap();
    let mut response: Option<Vec<u8>> = None;
    for _ in 0..200 {
        harness.drive().await;
        // Netstack egress is mirrored into app_ingress by drive().
        while let Some(pkt) = harness.app_ingress.pop_front() {
            if let Some(header) = PacketHeader::parse(&pkt) {
                if header.protocol == 17 && header.src_port == echo_addr.port() {
                    response = Some(pkt);
                    break;
                }
            }
        }
        tokio::time::sleep(std::time::Duration::from_millis(1)).await;
        if response.is_some() {
            break;
        }
    }
    let response = response.expect("netstack must emit a UDP response packet");
    let header = PacketHeader::parse(&response).unwrap();
    assert_eq!(
        header.src_ip,
        IpAddr::V4(echo_ip),
        "src must masquerade as the original target"
    );
    assert_eq!(header.dst_ip, IpAddr::V4(CLIENT_ADDR));
    assert_eq!(header.src_port, echo_addr.port());
    assert_eq!(header.dst_port, app_port);

    // IPv4 header checksum must be valid.
    let mut stripped = response.clone();
    stripped[10..12].copy_from_slice(&[0, 0]);
    assert_eq!(
        internet_checksum(&stripped[..20]).to_be_bytes(),
        response[10..12]
    );

    // UDP payload content must survive the round trip.
    let udp = super::packet::udp_payload(&response, &header).unwrap();
    assert_eq!(udp, payload);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unsupported_outbound_resets_flows_instead_of_leaking() {
    let (egress_tx, egress_rx) = tokio::sync::mpsc::channel(4096);
    let core = NetstackCore::new(
        TcpOutbound::Unsupported {
            protocol: "hysteria2",
            reason: "test".to_string(),
        },
        egress_tx,
    );
    let mut harness = Harness::new(core, egress_rx);

    let handle = harness.client_sockets.add(app_client_socket());
    // Any address works — the flow must be RST'd before any dial attempt,
    // never silently relayed direct.
    let remote = (
        IpAddress::Ipv4(Ipv4Address(Ipv4Addr::new(203, 0, 113, 7).octets())),
        443u16,
    );
    let local = (IpAddress::Ipv4(Ipv4Address(CLIENT_ADDR.octets())), 40100u16);
    {
        let cx = harness.client_iface.context();
        harness
            .client_sockets
            .get_mut::<TcpSocket>(handle)
            .connect(cx, remote, local)
            .expect("client connect");
    }

    let mut saw_rst = false;
    for _ in 0..300 {
        harness.drive().await;
        // Netstack egress (the RST) is mirrored into app_ingress by drive().
        while let Some(pkt) = harness.app_ingress.pop_front() {
            if let Some(header) = PacketHeader::parse(&pkt) {
                if let Some(flags) = header.tcp_flags(&pkt) {
                    if flags & 0x04 != 0 {
                        saw_rst = true;
                    }
                }
            }
        }
        tokio::time::sleep(std::time::Duration::from_millis(1)).await;
        if saw_rst && harness.core.tcp_flow_count() == 0 {
            break;
        }
    }
    assert!(saw_rst, "unsupported outbound must RST the flow (no silent leak)");
    assert_eq!(harness.core.tcp_flow_count(), 0, "refused flow must retire");
}
