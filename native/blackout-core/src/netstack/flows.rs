//! Flow tables & upstream pump tasks for the netstack.

use std::collections::VecDeque;
use std::net::{IpAddr, SocketAddr};
use std::time::Duration;

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
    DialFailed,
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
        // Bound connection establishment, including the proxy handshake.
        // Dropping the flow receiver also cancels an in-flight dial.
        let stream = match tokio::select! {
            result = bounded_dial(outbound.connect_tcp(dst), Duration::from_secs(15)) => result,
            _ = to_netstack.closed() => return,
        } {
            Ok(stream) => stream,
            Err(error) => {
                tracing::warn!(error_kind = ?error.kind(), "upstream dial failed; aborting flow");
                let _ = to_netstack.send(UpstreamMsg::DialFailed).await;
                return;
            }
        };
        tracing::debug!("upstream established");
        let (mut read_half, mut write_half) = tokio::io::split(stream);
        let mut buf = vec![0u8; 16384];
        let mut read_done = false;
        let mut write_closed = false;

        loop {
            tokio::select! {
                biased;

                _ = to_netstack.closed() => break,

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
                    Some(UpstreamMsg::DialFailed) => break,
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
        tracing::debug!("upstream pump finished");
    });
}

/// Bound any asynchronous dial without exposing endpoint or peer data.
async fn bounded_dial<T>(
    dial: impl std::future::Future<Output = std::io::Result<T>>,
    timeout: Duration,
) -> std::io::Result<T> {
    tokio::time::timeout(timeout, dial)
        .await
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::TimedOut, "upstream dial timed out"))?
}

#[cfg(test)]
mod dial_tests {
    use super::*;

    #[tokio::test]
    async fn stalled_handshake_is_bounded() {
        let pending = std::future::pending::<std::io::Result<()>>();
        let result = bounded_dial(pending, Duration::from_millis(20)).await;
        assert_eq!(result.unwrap_err().kind(), std::io::ErrorKind::TimedOut);
    }

    #[tokio::test]
    async fn successful_and_failed_dials_keep_their_result() {
        let timeout = Duration::from_secs(1);
        assert_eq!(bounded_dial(async { Ok(42) }, timeout).await.unwrap(), 42);
        let error = bounded_dial(
            async { Err::<(), _>(std::io::Error::from(std::io::ErrorKind::ConnectionRefused)) },
            timeout,
        )
        .await
        .unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::ConnectionRefused);
    }
}
