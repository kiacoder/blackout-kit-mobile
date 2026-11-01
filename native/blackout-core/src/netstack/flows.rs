//! Flow tables & upstream pump tasks for the netstack.

use std::collections::VecDeque;
use std::net::{IpAddr, SocketAddr};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::mpsc;

use crate::outbound::TcpOutbound;

/// 4-tuple identifying a flow (app side + target side).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub src: IpAddr,
    pub src_port: u16,
    pub dst: IpAddr,
    pub dst_port: u16,
}

impl FlowKey {
    pub fn target(&self) -> SocketAddr {
        SocketAddr::new(self.dst, self.dst_port)
    }
}

/// Messages flowing from the upstream pump task back into the netstack.
#[derive(Debug)]
pub enum UpstreamMsg {
    /// Bytes read from the upstream stream, destined for the app.
    Data(Vec<u8>),
    /// Upstream stream reached EOF (server closed its side).
    Eof,
    /// The outbound refused or failed to dial; the flow must be aborted
    /// (RST toward the app — never silently dropped).
    DialFailed(String),
}

/// A TCP flow being relayed through the smoltcp netstack.
pub struct TcpFlow {
    pub handle: smoltcp::iface::SocketHandle,
    pub created_ms: i64,
    /// True once the upstream dial has been spawned.
    pub connecting: bool,
    /// Upstream → netstack channel end (netstack receives from it).
    pub up_rx: Option<mpsc::Receiver<UpstreamMsg>>,
    /// Netstack → upstream channel end (netstack sends through it).
    pub up_tx: Option<mpsc::Sender<UpstreamMsg>>,
    /// Upstream data waiting for room in the smoltcp tx buffer.
    pub pending_to_socket: VecDeque<Vec<u8>>,
    /// App data waiting for room in the upstream channel.
    pub pending_to_upstream: VecDeque<Vec<u8>>,
    /// Set on DialFailed or unrecoverable socket errors → RST + remove.
    pub dead: bool,
    /// True once one poll has run after `dead` was set (RST emitted).
    pub rst_flushed: bool,
    /// Upstream EOF seen → FIN the socket toward the app.
    pub upstream_eof_seen: bool,
    /// The app sent its FIN (recv returned an error).
    pub peer_eof_seen: bool,
}

impl TcpFlow {
    pub fn new(handle: smoltcp::iface::SocketHandle, created_ms: i64) -> Self {
        Self {
            handle,
            created_ms,
            connecting: false,
            up_rx: None,
            up_tx: None,
            pending_to_socket: VecDeque::new(),
            pending_to_upstream: VecDeque::new(),
            dead: false,
            rst_flushed: false,
            upstream_eof_seen: false,
            peer_eof_seen: false,
        }
    }

    /// Both halves have seen EOF and all data has been handed over — the
    /// smoltcp socket is only waiting for the FIN exchange to finish.
    pub fn quiesced(&self) -> bool {
        self.upstream_eof_seen
            && self.peer_eof_seen
            && self.pending_to_socket.is_empty()
            && self.pending_to_upstream.is_empty()
    }
}

/// A UDP flow: one real datagram socket per app-side 4-tuple.
pub struct UdpFlow {
    pub socket: tokio::net::UdpSocket,
    pub last_active_ms: i64,
}

/// Spawns the bidirectional upstream pump for one TCP flow.
///
/// The pump owns the upstream stream; it exchanges data with the netstack
/// core through two channels. On EOF in either direction it propagates a
/// graceful close (shutdown → FIN) instead of tearing the connection down.
pub(super) fn spawn_upstream_pump(
    outbound: TcpOutbound,
    dst: SocketAddr,
    to_netstack: mpsc::Sender<UpstreamMsg>,
    mut from_netstack: mpsc::Receiver<UpstreamMsg>,
) {
    tokio::spawn(async move {
        let stream = match outbound.connect_tcp(dst).await {
            Ok(stream) => stream,
            Err(error) => {
                tracing::warn!(target = %dst, error = %error, "upstream dial failed; aborting flow");
                let _ = to_netstack.send(UpstreamMsg::DialFailed(error.to_string())).await;
                return;
            }
        };
        tracing::debug!(target = %dst, "upstream established");
        let (mut read_half, mut write_half) = tokio::io::split(stream);
        let mut buf = vec![0u8; 16384];
        let mut read_done = false;
        let mut write_closed = false;

        loop {
            tokio::select! {
                biased;

                // Netstack → upstream
                maybe = from_netstack.recv(), if !write_closed => match maybe {
                    Some(UpstreamMsg::Data(chunk)) => {
                        if write_half.write_all(&chunk).await.is_err() {
                            break;
                        }
                    }
                    Some(UpstreamMsg::Eof) | None => {
                        // App closed its side (or netstack dropped us):
                        // propagate a FIN upstream and drain remaining reads.
                        let _ = write_half.shutdown().await;
                        write_closed = true;
                    }
                    Some(UpstreamMsg::DialFailed(_)) => break,
                },

                // Upstream → netstack
                read = read_half.read(&mut buf), if !read_done => match read {
                    Ok(0) | Err(_) => {
                        let _ = to_netstack.send(UpstreamMsg::Eof).await;
                        read_done = true;
                    }
                    Ok(n) => {
                        if to_netstack
                            .send(UpstreamMsg::Data(buf[..n].to_vec()))
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                },

                else => break,
            }
        }
        tracing::debug!(target = %dst, "upstream pump finished");
    });
}
