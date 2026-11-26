// SPDX-License-Identifier: MIT
//go:build linux

package tun

import (
	"errors"
	"runtime"
	"testing"

	"golang.org/x/sys/unix"
)

// New app contract: CreateUnmonitoredTUNFromFD consumes fd even on failure.
// Use /dev/null so SetNonblock succeeds but TUNGETIFF deterministically fails.
func TestBlackoutFailedTUNConsumesFD(t *testing.T) {
	fd, err := unix.Open("/dev/null", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	dev, _, err := CreateUnmonitoredTUNFromFD(fd)
	if err == nil {
		dev.Close()
		t.Fatal("non-TUN descriptor was accepted")
	}
	if dev != nil {
		t.Fatal("failed initialization returned a device")
	}
	_, err = unix.FcntlInt(uintptr(fd), unix.F_GETFD, 0)
	if !errors.Is(err, unix.EBADF) {
		// Do not close the raw number here: the old core still owns an os.File
		// finalizer. Let GC close that wrapper rather than create a double close.
		runtime.GC()
		t.Fatal("failed TUN initialization did not consume the descriptor")
	}
}

func TestBlackoutRejectedTUNDoesNotCloseReusedFD(t *testing.T) {
	reused := 0
	for i := 0; i < 100; i++ {
		fd, err := unix.Open("/dev/null", unix.O_RDWR|unix.O_CLOEXEC, 0)
		if err != nil {
			t.Fatal(err)
		}
		dev, _, err := CreateUnmonitoredTUNFromFD(fd)
		if err == nil {
			dev.Close()
			t.Fatal("non-TUN descriptor was accepted")
		}
		if _, err := unix.FcntlInt(uintptr(fd), unix.F_GETFD, 0); !errors.Is(err, unix.EBADF) {
			runtime.GC()
			t.Fatal("descriptor not consumed")
		}
		replacement, err := unix.Open("/dev/null", unix.O_RDWR|unix.O_CLOEXEC, 0)
		if err != nil {
			t.Fatal(err)
		}
		if replacement == fd {
			reused++
		}
		runtime.GC()
		_, probeErr := unix.FcntlInt(uintptr(replacement), unix.F_GETFD, 0)
		unix.Close(replacement)
		if probeErr != nil {
			t.Fatal("replacement descriptor was closed unexpectedly")
		}
	}
	if reused == 0 {
		t.Fatal("fixture did not exercise descriptor-number reuse")
	}
}
