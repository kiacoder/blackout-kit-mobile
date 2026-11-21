// These tests are overlaid onto the pinned upstream AWG device test package.
// They reuse its real loopback UDP peers and in-memory TUN fixtures, not Android.
// No upstream/module-cache file is modified and no deployment key is used.
package device

import "testing"

func TestBlackoutAWGAdvancedPackets(t *testing.T) {
	goroutineLeakCheck(t)
	pair := genTestPair(t, true,
		"jc", "3", "jmin", "64", "jmax", "128",
		"s1", "15", "s2", "18", "s3", "20", "s4", "25",
		"h1", "123456-123500", "h2", "67543-67550",
		"h3", "123123-123200", "h4", "32345-32350",
		"i1", "<b 0xf6ab3267fa><t><r 10>",
		"i2", "<b 0xf6ab><rc 10>",
		"i3", "<b 0xf6ab><rd 10>",
		"i4", "<b 0xf6ab><r 20>",
		"i5", "<b 0xf6ab><r 25>",
	)
	if t.Failed() {
		t.FailNow()
	} // Upstream helper reports setup errors without aborting.
	for n := 0; n < 3; n++ {
		pair.Send(t, Ping, nil)
		pair.Send(t, Pong, nil)
	}
}

func TestBlackoutAWGInvalidNativeSettings(t *testing.T) {
	pair := genTestPair(t, true)
	if t.Failed() {
		t.FailNow()
	}
	for _, settings := range []string{"private_key=invalid\n", "jc=not-a-number\n", "h1=not-a-header\n", "i1=<c>\n"} {
		if err := pair[0].dev.IpcSet(settings); err == nil {
			t.Fatal("Native parser accepted an invalid setting")
		}
	}
	// An invalid setter must not silently destroy the existing working session.
	pair.Send(t, Ping, nil)
	pair.Send(t, Pong, nil)
}
