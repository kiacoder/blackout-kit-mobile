// SPDX-License-Identifier: MIT
// Reuses upstream MIT-licensed test helpers. No Android/JNI execution claimed.
package device

import (
	"testing"
	"time"
)

func TestBlackoutDeviceClosedSignal(t *testing.T) {
	goroutineLeakCheck(t)
	pair := genTestPair(t, false)
	for i := range pair {
		dev := pair[i].dev
		select {
		case <-dev.Wait():
			t.Fatal("new device reported closed")
		default:
		}
		// A network down/up cycle is not a terminal device closure. Polling
		// this channel must not be confused with handshake/reachability status.
		if err := dev.Down(); err != nil {
			t.Fatal("down failed")
		}
		select {
		case <-dev.Wait():
			t.Fatal("down incorrectly closed device")
		default:
		}
		if err := dev.Up(); err != nil {
			t.Fatal("up failed")
		}
		dev.Close()
		select {
		case <-dev.Wait():
		case <-time.After(3 * time.Second):
			t.Fatal("closed device signal missing")
		}
		dev.Close() // idempotent; upstream cleanup will call Close again too
	}
}
