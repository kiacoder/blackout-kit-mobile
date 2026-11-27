package com.blackoutkit.vpn;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.VpnService;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Base64;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.io.DataInputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Private Android load and optional isolated emulator traffic test. */
public final class OpenVpnCandidateAcceptance extends Instrumentation {
    private String fixture;
    private String mode;
    private String phase = "load";

    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        fixture = args.getString("fixture");
        mode = args.getString("mode", "cert");
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            require("com.blackoutkit.vpn.openvpntest".equals(getTargetContext().getPackageName()));
            loadContract();
            if (fixture != null) trafficContract();
            result.putString("stream", "\nOPENVPN_CANDIDATE_LOAD_PASS\n"
                    + (fixture != null ? "OPENVPN_ANDROID_TRAFFIC_PASS\n" : ""));
            finish(Activity.RESULT_OK, result);
        } catch (Exception | LinkageError | AssertionError failure) {
            result.putString("stream", "\nOPENVPN_CANDIDATE_FAIL phase=" + phase
                    + " type=" + failure.getClass().getSimpleName() + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private void loadContract() {
        OpenVpnNativeBridge bridge = OpenVpnNativeBridge.INSTANCE;
        bridge.loadCandidate();
        byte[] empty = new byte[0];
        long handle = bridge.nativeCreate();
        require(handle > 0);
        try {
            require(bridge.nativeCreate() == 0);
            require(!bridge.nativeRelease(handle + 1));
            require(!bridge.nativeReconnect(handle));
            bridge.nativeCancel(handle);
            require(bridge.nativeRunV3(handle, null, empty, new byte[][] {empty, empty, empty}) != 0);
            require(bridge.nativeRunV3(handle, null, empty, new byte[][] {empty, empty, empty}) != 0);
        } finally {
            require(bridge.nativeRelease(handle));
        }
        require(!bridge.nativeRelease(handle));
        long next = bridge.nativeCreate();
        require(next > handle);
        try {
            require(!bridge.nativeReconnect(handle));
            bridge.nativeCancel(handle);
            require(bridge.nativeRunV3(handle, null, empty, new byte[][] {empty, empty, empty}) != 0);
        } finally {
            require(bridge.nativeRelease(next));
        }
    }

    private void trafficContract() throws Exception {
        phase = "consent";
        Context context = getTargetContext();
        // Never bypass VPN consent in the application. The emulator runner
        // must grant it explicitly for the private test package beforehand.
        require(VpnService.prepare(context) == null);
        String profile = new String(Base64.decode(fixture, Base64.DEFAULT), StandardCharsets.UTF_8);
        require(profile.contains("remote 10.0.2.2 11940\n"));
        require(profile.contains("verify-x509-name server name\n"));
        require(!BlackoutVpnService.Companion.isRunning());
        Intent start = new Intent(context, BlackoutVpnService.class);
        start.setAction(BlackoutVpnService.ACTION_CONNECT);
        start.putExtra(BlackoutVpnService.EXTRA_PROTOCOL, "openvpn");
        start.putExtra(BlackoutVpnService.EXTRA_OPENVPN_CONFIG, profile);
        start.putExtra(BlackoutVpnService.EXTRA_DISPLAY_NAME, "Synthetic fixture");
        start.putExtra(BlackoutVpnService.EXTRA_HOLD_ON_ENGINE_FAILURE, true);
        // Test only the app UID, not other apps or the emulator's traffic.
        start.putStringArrayListExtra(BlackoutVpnService.EXTRA_ALLOWED_APPS,
                new ArrayList<>(Arrays.asList(context.getPackageName())));
        if ("encrypted-login".equals(mode) || "login-only".equals(mode) || "hold".equals(mode)) {
            byte[] keyPassword = "encrypted-login".equals(mode)
                    ? "fixture-key-password".getBytes(StandardCharsets.UTF_8) : new byte[0];
            OpenVpnCredentials auth = new OpenVpnCredentials(
                    "fixture-user".getBytes(StandardCharsets.UTF_8),
                    "fixture-password".getBytes(StandardCharsets.UTF_8), keyPassword);
            start.putExtra(BlackoutVpnService.EXTRA_OPENVPN_AUTH_TOKEN,
                    OpenVpnCredentialHandoff.INSTANCE.stage(auth));
        }
        boolean customDns = "encrypted-login".equals(mode);
        String expectedDns = customDns ? "10.77.0.53" : "10.77.0.1";
        if (customDns) {
            start.putStringArrayListExtra(BlackoutVpnService.EXTRA_OPENVPN_CUSTOM_DNS,
                    new ArrayList<>(Arrays.asList(expectedDns)));
        }
        boolean hold = "hold".equals(mode);
        if (hold) {
            phase = "baseline-sentinel";
            long baselineDeadline = SystemClock.elapsedRealtime() + 8000;
            boolean baseline = false;
            while (SystemClock.elapsedRealtime() < baselineDeadline && !baseline) {
                baseline = sentinelReachable();
            }
            require(baseline);
        }
        phase = "start";
        try {
            context.startForegroundService(start);
            long deadline = SystemClock.elapsedRealtime() + 40000;
            while (!BlackoutVpnService.Companion.isRunning()
                    && SystemClock.elapsedRealtime() < deadline) {
                SystemClock.sleep(100);
            }
            require(BlackoutVpnService.Companion.isRunning());
            phase = "routes";
            ConnectivityManager cm = context.getSystemService(ConnectivityManager.class);
            // VpnService.establish returns before the network agent's routing
            // update is visible to this UID. Allow bounded propagation.
            long routeDeadline = SystemClock.elapsedRealtime() + 8000;
            LinkProperties link = null;
            boolean vpnDefault = false;
            while (SystemClock.elapsedRealtime() < routeDeadline) {
                Network network = cm.getActiveNetwork();
                NetworkCapabilities caps = network == null ? null : cm.getNetworkCapabilities(network);
                vpnDefault = caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
                if (vpnDefault) {
                    link = cm.getLinkProperties(network);
                    if (link != null && link.getDnsServers().contains(InetAddress.getByName(expectedDns))
                            && link.getRoutes().stream().anyMatch(r -> r.isDefaultRoute()
                            && r.getDestination().getAddress().getAddress().length == 4)) break;
                }
                SystemClock.sleep(100);
            }
            phase = "vpn-default";
            require(vpnDefault);
            phase = "dns";
            require(link != null && link.getDnsServers().contains(InetAddress.getByName(expectedDns)));
            if (customDns) require(!link.getDnsServers().contains(InetAddress.getByName("10.77.0.1")));
            phase = "ipv4-default";
            require(link.getRoutes().stream().anyMatch(r -> r.isDefaultRoute()
                    && r.getDestination().getAddress().getAddress().length == 4));
            phase = "tcp";
            byte[] payload = "android-openvpn-echo".getBytes(StandardCharsets.UTF_8);
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress("10.77.0.1", 41004), 5000);
                socket.setSoTimeout(5000);
                socket.getOutputStream().write(payload);
                byte[] returned = new byte[payload.length];
                new DataInputStream(socket.getInputStream()).readFully(returned);
                require(Arrays.equals(payload, returned));
            }
            phase = "udp";
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setSoTimeout(5000);
                socket.connect(InetAddress.getByName("10.77.0.1"), 41002);
                socket.send(new DatagramPacket(payload, payload.length));
                DatagramPacket reply = new DatagramPacket(new byte[128], 128);
                socket.receive(reply);
                require(Arrays.equals(payload, Arrays.copyOf(reply.getData(), reply.getLength())));
            }
            phase = "dns-packet";
            dnsPacket(expectedDns);
            if (hold) {
                phase = "connected-sentinel";
                require(!sentinelReachable());
                phase = "server-stop";
                byte[] command = "stop-synthetic-server".getBytes(StandardCharsets.UTF_8);
                try (DatagramSocket control = new DatagramSocket()) {
                    control.setSoTimeout(5000);
                    control.connect(InetAddress.getByName("10.77.0.1"), 41005);
                    control.send(new DatagramPacket(command, command.length));
                    DatagramPacket ack = new DatagramPacket(new byte[128], 128);
                    control.receive(ack);
                    require(Arrays.equals(command, Arrays.copyOf(ack.getData(), ack.getLength())));
                }
                phase = "held";
                long holdDeadline = SystemClock.elapsedRealtime() + 60000;
                while (!BlackoutVpnService.Companion.isTunnelHeld()
                        && SystemClock.elapsedRealtime() < holdDeadline) {
                    SystemClock.sleep(100);
                }
                require(BlackoutVpnService.Companion.isTunnelHeld());
                require(!BlackoutVpnService.Companion.isRunning());
                require(!BlackoutVpnService.Companion.isTunnelCleanupPending());
                phase = "held-sentinel";
                require(!sentinelReachable());
            }
        } finally {
            String prior = phase;
            phase = "stop";
            CountDownLatch ended = new CountDownLatch(1);
            boolean[] success = {false};
            BlackoutVpnService.Companion.setOnTeardownComplete(ok -> {
                success[0] = ok;
                ended.countDown();
                return kotlin.Unit.INSTANCE;
            });
            Intent stop = new Intent(context, BlackoutVpnService.class);
            stop.setAction(BlackoutVpnService.ACTION_DISCONNECT);
            context.startService(stop);
            require(ended.await(15, TimeUnit.SECONDS) && success[0]);
            require(!BlackoutVpnService.Companion.isRunning());
            require(!BlackoutVpnService.Companion.isTunnelHeld());
            require(!BlackoutVpnService.Companion.isTunnelCleanupPending());
            if (hold && "held-sentinel".equals(prior)) {
                phase = "released-sentinel";
                long until = SystemClock.elapsedRealtime() + 8000;
                boolean reachable = false;
                while (SystemClock.elapsedRealtime() < until && !reachable) {
                    reachable = sentinelReachable();
                }
                require(reachable);
            }
            phase = prior;
        }
    }

    private static void dnsPacket(String resolver) throws Exception {
        byte[] label = "blackout-fixture".getBytes(StandardCharsets.US_ASCII);
        byte[] query = new byte[12 + 1 + label.length + 1 + 4 + 1 + 4];
        query[0] = 0x12;
        query[1] = 0x34;
        query[2] = 1;
        query[5] = 1;
        query[12] = (byte) label.length;
        System.arraycopy(label, 0, query, 13, label.length);
        int offset = 13 + label.length;
        query[offset++] = 4;
        System.arraycopy("test".getBytes(StandardCharsets.US_ASCII), 0, query, offset, 4);
        offset += 5;
        query[offset + 1] = 1;
        query[offset + 3] = 1;
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.connect(InetAddress.getByName(resolver), 53);
            socket.setSoTimeout(5000);
            socket.send(new DatagramPacket(query, query.length));
            DatagramPacket reply = new DatagramPacket(new byte[512], 512);
            socket.receive(reply);
            byte[] bytes = reply.getData();
            int n = reply.getLength();
            require(n == query.length + 16);
            require(bytes[0] == 0x12 && bytes[1] == 0x34 && bytes[2] == (byte) 0x81
                    && bytes[3] == (byte) 0x80 && bytes[7] == 1);
            require(Arrays.equals(Arrays.copyOfRange(bytes, n - 4, n),
                    InetAddress.getByName("192.0.2.53").getAddress()));
        }
    }

    private static boolean sentinelReachable() {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("10.0.2.2", 11940), 1500);
            return true;
        } catch (java.io.IOException unavailable) {
            return false;
        }
    }

    private static void require(boolean value) {
        if (!value) throw new AssertionError("OpenVPN native contract");
    }
}
