// Linux kernel-TUN test fixture, NOT an Android adapter or shipped executable.
// Build against pinned AWG. The test driver may substitute the pinned WG import
// prefix in a disposable build directory to exercise WireGuard independently.
package main

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
	"os/signal"
	"syscall"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/amnezia-vpn/amneziawg-go/v3/tun"
)

func main() {
	if len(os.Args) == 2 && os.Args[1] == "keygen" {
		key, err := ecdh.X25519().GenerateKey(rand.Reader)
		if err != nil {
			os.Exit(2)
		}
		json.NewEncoder(os.Stdout).Encode(map[string]string{"private": hex.EncodeToString(key.Bytes()), "public": hex.EncodeToString(key.PublicKey().Bytes())})
		return
	}
	if len(os.Args) != 3 {
		os.Exit(2)
	}
	config, err := os.ReadFile(os.Args[2])
	if err != nil {
		os.Exit(2)
	}
	tunnel, err := tun.CreateTUN(os.Args[1], 1420)
	if err != nil {
		os.Exit(3)
	}
	core := device.NewDevice(tunnel, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	defer core.Close()
	if core.IpcSet(string(config)) != nil {
		os.Exit(4)
	}
	if core.Up() != nil {
		os.Exit(5)
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	<-signals
}
