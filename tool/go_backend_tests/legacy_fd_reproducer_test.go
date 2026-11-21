// SPDX-License-Identifier: MIT
//go:build linux

package tun

// DIAGNOSTIC ONLY: run against the pristine pinned core, never the patched core.
// Deliberately reproduces the old JNI raw-close-on-error behavior, which is
// forbidden by the new consumes-on-error contract. Not part of the regular suite.
import (
    "runtime"
    "testing"
    "time"

    "golang.org/x/sys/unix"
)

func TestBlackoutLegacyBridgeFDReuse(t *testing.T) {
    fd, err := unix.Open("/dev/null", unix.O_RDWR|unix.O_CLOEXEC, 0)
    if err != nil { t.Fatal(err) }
    dev, _, err := CreateUnmonitoredTUNFromFD(fd)
    if err == nil { dev.Close(); t.Fatal("non-TUN descriptor unexpectedly accepted") }
    unix.Close(fd) // exact original JNI error path
    replacement, err := unix.Open("/dev/null", unix.O_RDWR|unix.O_CLOEXEC, 0)
    if err != nil { t.Fatal(err) }
    if replacement != fd {
        unix.Close(replacement)
        t.Fatal("fixture did not reuse the descriptor number")
    }
    runtime.GC()
    // Give the runtime finalizer goroutine an execution window, not a retry.
    time.Sleep(100 * time.Millisecond)
    _, err = unix.FcntlInt(uintptr(replacement), unix.F_GETFD, 0)
    if err != nil { t.Fatal("old TUN finalizer closed the replacement descriptor") }
    unix.Close(replacement)
}
