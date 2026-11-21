// SPDX-License-Identifier: MIT
// Uses the pinned upstream device test helpers (MIT, WireGuard LLC).
// The barrier forces the first TUN read to start BEFORE S4 is configured.
// No packet retries, extra handshakes or weaker assertions are used.
package device

import (
	"fmt"
	"net/netip"
	"sync"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun/tuntest"
)

type blackoutReadBarrier struct {
	tun.Device
	once    sync.Once
	entered chan int
}

func (b *blackoutReadBarrier) Read(packets [][]byte, sizes []int, offset int) (int, error) {
	b.once.Do(func() { b.entered <- offset })
	return b.Device.Read(packets, sizes, offset)
}

func TestBlackoutAWGReadBeforeConfiguration(t *testing.T) {
	blackoutReadBeforeConfiguration(t, 25)
}

func TestBlackoutAWGInitialPaddingVariants(t *testing.T) {
	for _, padding := range []uint32{0, 1, 64, 1000} {
		t.Run(fmt.Sprint(padding), func(t *testing.T) { blackoutReadBeforeConfiguration(t, padding) })
	}
}

func blackoutReadBeforeConfiguration(t *testing.T, padding uint32) {
	t.Helper()
	var pair testPair
	cfg, endpoints := genConfigs(t,
		"s4", fmt.Sprint(padding), "h1", "123456-123500", "h2", "67543-67550",
		"h3", "123123-123200", "h4", "32345-32350")
	for i := range pair {
		peer := &pair[i]
		peer.tun = tuntest.NewChannelTUN()
		peer.ip = netip.AddrFrom4([4]byte{1, 0, 0, byte(i + 1)})
		barrier := &blackoutReadBarrier{Device: peer.tun.TUN(), entered: make(chan int, 1)}
		peer.dev = NewDevice(barrier, conn.NewDefaultBind(), NewLogger(LogLevelSilent, ""))
		t.Cleanup(peer.dev.Close)
		select {
		case offset := <-barrier.entered:
			if offset != MessageTransportHeaderSize {
				t.Fatalf("Unexpected initial TUN offset: %d", offset)
			}
		case <-time.After(3 * time.Second):
			t.Fatal("TUN reader did not enter the barrier")
		}
		if err := peer.dev.IpcSet(cfg[i]); err != nil {
			t.Fatal("Synthetic device configuration rejected")
		}
		if peer.dev.paddings.transport.Load() != padding {
			t.Fatal("S4 not applied")
		}
		if err := peer.dev.Up(); err != nil {
			t.Fatal("Synthetic device could not start")
		}
		endpoints[i^1] = fmt.Sprintf(endpoints[i^1], peer.dev.net.port)
	}
	for i := range pair {
		if err := pair[i].dev.IpcSet(endpoints[i]); err != nil {
			t.Fatal("Loopback endpoint rejected")
		}
	}
	pair.Send(t, Ping, nil)
	pair.Send(t, Pong, nil)
}
