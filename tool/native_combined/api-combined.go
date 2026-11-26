package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"math"
	"sync"

	awgconn "github.com/amnezia-vpn/amneziawg-go/v3/conn"
	awgdevice "github.com/amnezia-vpn/amneziawg-go/v3/device"
	awgtun "github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"golang.org/x/sys/unix"
	wgconn "golang.zx2c4.com/wireguard/conn"
	wgdevice "golang.zx2c4.com/wireguard/device"
	wgtun "golang.zx2c4.com/wireguard/tun"
)

const (
	wgVersionString  = "f333402"
	awgVersionString = "v3.1.20260814"
)

type wgHandle struct {
	device *wgdevice.Device
}

type awgHandle struct {
	device *awgdevice.Device
}

var (
	wgMu      sync.Mutex
	wgHandles = make(map[int32]wgHandle)
	awgMu      sync.Mutex
	awgHandles = make(map[int32]awgHandle)
)

func nextWGHandle() int32 {
	for i := int32(0); i < math.MaxInt32; i++ {
		if _, ok := wgHandles[i]; !ok {
			return i
		}
	}
	return -1
}

func nextAWGHandle() int32 {
	for i := int32(0); i < math.MaxInt32; i++ {
		if _, ok := awgHandles[i]; !ok {
			return i
		}
	}
	return -1
}

//export wgTurnOn
func wgTurnOn(interfaceName string, tunFd int32, settings string) int32 {
	wgMu.Lock()
	defer wgMu.Unlock()

	tunDevice, _, err := wgtun.CreateUnmonitoredTUNFromFD(int(tunFd))
	if err != nil {
		// The patched core consumes tunFd on every return path.
		return -1
	}
	device := wgdevice.NewDevice(
		tunDevice,
		wgconn.NewStdNetBind(),
		wgdevice.NewLogger(wgdevice.LogLevelSilent, ""),
	)
	if err = device.IpcSet(settings); err != nil {
		device.Close()
		return -1
	}
	device.DisableSomeRoamingForBrokenMobileSemantics()
	if err = device.Up(); err != nil {
		device.Close()
		return -1
	}
	handle := nextWGHandle()
	if handle < 0 {
		device.Close()
		return -1
	}
	wgHandles[handle] = wgHandle{device: device}
	return handle
}

//export wgTurnOff
func wgTurnOff(handle int32) {
	wgMu.Lock()
	defer wgMu.Unlock()
	entry, ok := wgHandles[handle]
	if !ok {
		return
	}
	delete(wgHandles, handle)
	entry.device.Close()
}

//export wgGetSocketV4
func wgGetSocketV4(handle int32) int32 {
	wgMu.Lock()
	defer wgMu.Unlock()
	entry, ok := wgHandles[handle]
	if !ok {
		return -1
	}
	bind, _ := entry.device.Bind().(wgconn.PeekLookAtSocketFd)
	if bind == nil {
		return -1
	}
	fd, err := bind.PeekLookAtSocketFd4()
	if err != nil {
		return -1
	}
	return int32(fd)
}

//export wgGetSocketV6
func wgGetSocketV6(handle int32) int32 {
	wgMu.Lock()
	defer wgMu.Unlock()
	entry, ok := wgHandles[handle]
	if !ok {
		return -1
	}
	bind, _ := entry.device.Bind().(wgconn.PeekLookAtSocketFd)
	if bind == nil {
		return -1
	}
	fd, err := bind.PeekLookAtSocketFd6()
	if err != nil {
		return -1
	}
	return int32(fd)
}

//export wgGetConfig
func wgGetConfig(handle int32) *C.char {
	wgMu.Lock()
	defer wgMu.Unlock()
	entry, ok := wgHandles[handle]
	if !ok {
		return nil
	}
	settings, err := entry.device.IpcGet()
	if err != nil {
		return nil
	}
	return C.CString(settings)
}

//export wgVersion
func wgVersion() *C.char {
	return C.CString(wgVersionString)
}

//export wgIsClosed
func wgIsClosed(handle int32) int32 {
	wgMu.Lock()
	defer wgMu.Unlock()
	entry, ok := wgHandles[handle]
	if !ok {
		return 1
	}
	select {
	case <-entry.device.Wait():
		return 1
	default:
		return 0
	}
}

//export awgTurnOn
func awgTurnOn(interfaceName string, tunFd int32, settings string) int32 {
	awgMu.Lock()
	defer awgMu.Unlock()

	tunDevice, _, err := awgtun.CreateUnmonitoredTUNFromFD(int(tunFd))
	if err != nil {
		// The patched core consumes tunFd on every return path.
		return -1
	}
	device := awgdevice.NewDevice(
		tunDevice,
		awgconn.NewStdNetBind(),
		awgdevice.NewLogger(awgdevice.LogLevelSilent, ""),
	)
	if err = device.IpcSet(settings); err != nil {
		device.Close()
		return -1
	}
	device.DisableSomeRoamingForBrokenMobileSemantics()
	if err = device.Up(); err != nil {
		device.Close()
		return -1
	}
	handle := nextAWGHandle()
	if handle < 0 {
		device.Close()
		return -1
	}
	awgHandles[handle] = awgHandle{device: device}
	return handle
}

//export awgTurnOff
func awgTurnOff(handle int32) {
	awgMu.Lock()
	defer awgMu.Unlock()
	entry, ok := awgHandles[handle]
	if !ok {
		return
	}
	delete(awgHandles, handle)
	entry.device.Close()
}

//export awgGetSocketV4
func awgGetSocketV4(handle int32) int32 {
	awgMu.Lock()
	defer awgMu.Unlock()
	entry, ok := awgHandles[handle]
	if !ok {
		return -1
	}
	bind, _ := entry.device.Bind().(awgconn.PeekLookAtSocketFd)
	if bind == nil {
		return -1
	}
	fd, err := bind.PeekLookAtSocketFd4()
	if err != nil {
		return -1
	}
	return int32(fd)
}

//export awgGetSocketV6
func awgGetSocketV6(handle int32) int32 {
	awgMu.Lock()
	defer awgMu.Unlock()
	entry, ok := awgHandles[handle]
	if !ok {
		return -1
	}
	bind, _ := entry.device.Bind().(awgconn.PeekLookAtSocketFd)
	if bind == nil {
		return -1
	}
	fd, err := bind.PeekLookAtSocketFd6()
	if err != nil {
		return -1
	}
	return int32(fd)
}

//export awgGetConfig
func awgGetConfig(handle int32) *C.char {
	awgMu.Lock()
	defer awgMu.Unlock()
	entry, ok := awgHandles[handle]
	if !ok {
		return nil
	}
	settings, err := entry.device.IpcGet()
	if err != nil {
		return nil
	}
	return C.CString(settings)
}

//export awgVersion
func awgVersion() *C.char {
	return C.CString(awgVersionString)
}

//export awgIsClosed
func awgIsClosed(handle int32) int32 {
	awgMu.Lock()
	defer awgMu.Unlock()
	entry, ok := awgHandles[handle]
	if !ok {
		return 1
	}
	select {
	case <-entry.device.Wait():
		return 1
	default:
		return 0
	}
}

func main() {
	_ = unix.EINTR // Keep x/sys pinned as an explicit direct dependency.
}
