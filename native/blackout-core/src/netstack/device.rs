//! smoltcp phy adapter: bridges the netstack to the TUN device through
//! owned packet queues/channels instead of real file descriptors, which
//! makes the whole netstack testable on the host.

use std::collections::VecDeque;

use smoltcp::phy::{Device, DeviceCapabilities, Medium};
use smoltcp::time::Instant;
use tokio::sync::mpsc;

/// Device fed by an in-memory ingress queue (packets captured from the TUN
/// fd by the driver task) whose egress goes out through a tokio channel
/// (drained by the writer task that writes back to the TUN fd).
pub struct ChannelDevice {
    pub ingress: VecDeque<Vec<u8>>,
    pub egress_tx: mpsc::Sender<Vec<u8>>,
    pub mtu: usize,
}

impl ChannelDevice {
    pub fn new(egress_tx: mpsc::Sender<Vec<u8>>, mtu: usize) -> Self {
        Self {
            ingress: VecDeque::new(),
            egress_tx,
            mtu,
        }
    }
}

/// One raw IP packet waiting to be handed to smoltcp.
pub struct IngressToken(pub Vec<u8>);

impl smoltcp::phy::RxToken for IngressToken {
    fn consume<R, F>(self, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut packet = self.0;
        f(&mut packet)
    }
}

/// Egress token: smoltcp fills a buffer during `consume`, we ship it to the
/// TUN writer. If the egress channel is momentarily full the packet is
/// dropped — backpressure at packet granularity is the correct behavior for
/// a best-effort virtual link (the TCP retransmit timers recover losses).
pub struct EgressToken(pub mpsc::Sender<Vec<u8>>);

impl smoltcp::phy::TxToken for EgressToken {
    fn consume<R, F>(self, len: usize, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut buf = vec![0u8; len];
        let result = f(&mut buf);
        if let Err(error) = self.0.try_send(buf) {
            tracing::warn!(error = %error, "egress channel full; packet dropped");
        }
        result
    }
}

impl Device for ChannelDevice {
    type RxToken<'a> = IngressToken;
    type TxToken<'a> = EgressToken;

    fn receive(&mut self, _timestamp: Instant) -> Option<(Self::RxToken<'_>, Self::TxToken<'_>)> {
        let packet = self.ingress.pop_front()?;
        Some((IngressToken(packet), EgressToken(self.egress_tx.clone())))
    }

    fn transmit(&mut self, _timestamp: Instant) -> Option<Self::TxToken<'_>> {
        Some(EgressToken(self.egress_tx.clone()))
    }

    fn capabilities(&self) -> DeviceCapabilities {
        let mut caps = DeviceCapabilities::default();
        // TUN gives us raw IP packets with no link-layer header.
        caps.medium = Medium::Ip;
        // Must match VPN_MTU in BlackoutVpnService.kt.
        caps.max_transmission_unit = self.mtu;
        caps
    }
}
