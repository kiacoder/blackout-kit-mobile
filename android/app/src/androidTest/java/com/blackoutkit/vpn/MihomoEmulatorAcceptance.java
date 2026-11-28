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
import java.io.DataInputStream;
import java.io.File;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Disposable-emulator test: engine service UID and traffic probe UID are distinct. */
public final class MihomoEmulatorAcceptance extends Instrumentation {
    private static final String ENGINE_PACKAGE = "com.blackoutkit.vpn.mihomotest";
    private static final String PROBE_PACKAGE = "com.blackoutkit.vpn.openvpntest";
    private static final String READY = "mihomo-fixture-ready";
    private static final String STOP = "mihomo-fixture-stop";
    private static final String CONFIG = "{\"socks-port\":10808,\"allow-lan\":false,"
        + "\"bind-address\":\"127.0.0.1\",\"mode\":\"rule\",\"log-level\":\"warning\","
        + "\"geo-auto-update\":false,\"tun\":{\"enable\":false},"
        + "\"proxies\":[{\"name\":\"fixture\",\"type\":\"socks5\",\"server\":\"10.0.2.2\","
        + "\"port\":11940,\"udp\":true}],"
        + "\"proxy-groups\":[{\"name\":\"selected\",\"type\":\"select\",\"proxies\":[\"fixture\"]}],"
        + "\"rules\":[\"MATCH,selected\"]}";
    private String phase = "start";
    private boolean holdTest;

    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        holdTest = args != null && "hold".equals(args.getString("mode"));
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            serve();
            result.putString("stream", "\nMIHOMO_ANDROID_SERVICE_PASS\n");
            finish(Activity.RESULT_OK, result);
        } catch (Exception | LinkageError | AssertionError failure) {
            result.putString("stream", "\nMIHOMO_ANDROID_SERVICE_FAIL phase=" + phase
                + " type=" + failure.getClass().getSimpleName() + "\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private void serve() throws Exception {
        Context context = getTargetContext();
        require(ENGINE_PACKAGE.equals(context.getPackageName()));
        require(VpnService.prepare(context) == null);
        File ready = new File(context.getFilesDir(), READY);
        File stop = new File(context.getFilesDir(), STOP);
        File held = new File(context.getFilesDir(), "mihomo-fixture-held");
        ready.delete();
        stop.delete();
        held.delete();
        File direct = new File(context.getNoBackupFilesDir(), "direct-mihomo");
        File stale = new File(direct, "session-123.json");
        File staleMarker = new File(direct, "session-123.json.tun-ready");
        if (BuildConfig.ENABLE_MIHOMO_DIRECT_TUN) {
            require(direct.isDirectory() || direct.mkdirs());
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(stale)) {
                out.write("synthetic-stale".getBytes(StandardCharsets.US_ASCII));
            }
            require(staleMarker.exists() || staleMarker.createNewFile());
        }
        Intent start = new Intent(context, BlackoutVpnService.class);
        start.setAction(BlackoutVpnService.ACTION_CONNECT);
        start.putExtra(BlackoutVpnService.EXTRA_PROTOCOL, "mihomo");
        start.putExtra(BlackoutVpnService.EXTRA_DISPLAY_NAME, "Synthetic Mihomo fixture");
        start.putExtra(BlackoutVpnService.EXTRA_MIHOMO_CONFIG, CONFIG);
        start.putExtra(BlackoutVpnService.EXTRA_HOLD_ON_ENGINE_FAILURE, true);
        start.putStringArrayListExtra(BlackoutVpnService.EXTRA_ALLOWED_APPS,
                new ArrayList<>(Arrays.asList(PROBE_PACKAGE)));
        start.putStringArrayListExtra(BlackoutVpnService.EXTRA_DNS_SERVERS,
                new ArrayList<>(Arrays.asList("192.0.2.53")));
        try {
            context.startForegroundService(start);
            long deadline = SystemClock.elapsedRealtime() + 40000;
            while (!BlackoutVpnService.Companion.isRunning()
                    && SystemClock.elapsedRealtime() < deadline) {
                SystemClock.sleep(100);
            }
            phase = "engine-ready";
            require(BlackoutVpnService.Companion.isRunning());
            if (BuildConfig.ENABLE_MIHOMO_DIRECT_TUN) {
                require(!stale.exists() && !staleMarker.exists());
            }
            require(ready.createNewFile());
            phase = "probe";
            deadline = SystemClock.elapsedRealtime() + 45000;
            while (!stop.exists() && SystemClock.elapsedRealtime() < deadline) {
                if (holdTest) {
                    if (BlackoutVpnService.Companion.isTunnelHeld()) {
                        require(held.exists() || held.createNewFile());
                    }
                } else {
                    require(BlackoutVpnService.Companion.isRunning());
                }
                SystemClock.sleep(100);
            }
            require(stop.exists());
            if (holdTest) require(held.exists());
        } finally {
            String prior = phase;
            phase = "stop";
            ready.delete();
            stop.delete();
            held.delete();
            CountDownLatch ended = new CountDownLatch(1);
            boolean[] success = {false};
            BlackoutVpnService.Companion.setOnTeardownComplete(ok -> {
                success[0] = ok;
                ended.countDown();
                return kotlin.Unit.INSTANCE;
            });
            Intent disconnect = new Intent(context, BlackoutVpnService.class);
            disconnect.setAction(BlackoutVpnService.ACTION_DISCONNECT);
            context.startService(disconnect);
            require(ended.await(15, TimeUnit.SECONDS) && success[0]);
            require(!BlackoutVpnService.Companion.isRunning());
            require(!BlackoutVpnService.Companion.isTunnelCleanupPending());
            if (BuildConfig.ENABLE_MIHOMO_DIRECT_TUN) {
                String[] sessions = direct.list((dir, name) -> name.matches("session--?[0-9]+\\.json(\\.tun-ready)?"));
                require(sessions != null && sessions.length == 0);
            }
            phase = prior;
        }
    }

    static void probe(Context context, boolean directProbe) throws Exception {
        require(PROBE_PACKAGE.equals(context.getPackageName()));
        ConnectivityManager cm = context.getSystemService(ConnectivityManager.class);
        long until = SystemClock.elapsedRealtime() + 8000;
        boolean routed = false;
        while (SystemClock.elapsedRealtime() < until) {
            Network network = cm.getActiveNetwork();
            NetworkCapabilities caps = network == null ? null : cm.getNetworkCapabilities(network);
            LinkProperties lp = network == null ? null : cm.getLinkProperties(network);
            routed = caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                && lp != null && lp.getDnsServers().contains(InetAddress.getByName("192.0.2.53"))
                && lp.getRoutes().stream().anyMatch(r -> r.isDefaultRoute()
                    && r.getDestination().getAddress().getAddress().length == 4);
            if (routed) break;
            SystemClock.sleep(100);
        }
        require(routed);
        // In direct mode there must be no TCP listener at the old SOCKS port.
        // The probe APK uses the OpenVPN BuildConfig, so mode is passed in the
        // instrumentation arguments rather than inferred from its build flag.
        if (directProbe) {
            boolean refused = false;
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress("127.0.0.1", 10808), 1500);
            } catch (java.io.IOException unavailable) {
                refused = true;
            }
            require(refused);
        } else {
            // A different app UID must not negotiate an unauthenticated TCP session.
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress("127.0.0.1", 10808), 3000);
                socket.setSoTimeout(3000);
                socket.getOutputStream().write(new byte[] {5,1,0});
                require(socket.getInputStream().read() == 5);
                // The pinned server requests password auth even if not offered.
                // A strict RFC rejection (255) or challenge (2) is safe only
                // when incorrect credentials cannot complete authentication.
                int method = socket.getInputStream().read();
                require(method == 255 || method == 2);
                if (method == 2) {
                    byte[] invalid = "invalid".getBytes(StandardCharsets.US_ASCII);
                    socket.getOutputStream().write(new byte[] {1,7});
                    socket.getOutputStream().write(invalid);
                    socket.getOutputStream().write(7);
                    socket.getOutputStream().write(invalid);
                    require(socket.getInputStream().read() == 1);
                    require(socket.getInputStream().read() != 0);
                }
            }
        }
        byte[] payload = "mihomo-android-fixture-echo".getBytes(StandardCharsets.US_ASCII);
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("192.0.2.80", 41004), 5000);
            socket.setSoTimeout(5000);
            socket.getOutputStream().write(payload);
            byte[] returned = new byte[payload.length];
            new DataInputStream(socket.getInputStream()).readFully(returned);
            require(Arrays.equals(payload, returned));
        }
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.connect(InetAddress.getByName("192.0.2.80"), 41002);
            socket.setSoTimeout(5000);
            socket.send(new DatagramPacket(payload, payload.length));
            DatagramPacket reply = new DatagramPacket(new byte[128], 128);
            socket.receive(reply);
            require(Arrays.equals(payload, Arrays.copyOf(reply.getData(), reply.getLength())));
        }
        // Raw DNS query to the resolver installed in the VPN network.
        byte[] query = new byte[] {0x12,0x34,1,0,0,1,0,0,0,0,0,0,7,
            'f','i','x','t','u','r','e',4,'t','e','s','t',0,0,1,0,1};
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.connect(InetAddress.getByName("192.0.2.53"), 53);
            socket.setSoTimeout(5000);
            socket.send(new DatagramPacket(query, query.length));
            DatagramPacket reply = new DatagramPacket(new byte[128], 128);
            socket.receive(reply);
            int n = reply.getLength();
            byte[] data = reply.getData();
            require(n == query.length + 16 && data[0] == 0x12 && data[1] == 0x34);
            require(Arrays.equals(Arrays.copyOfRange(data,n-4,n),InetAddress.getByName("192.0.2.80").getAddress()));
        }
    }

    static void sentinel(Context context, boolean expected) {
        require(PROBE_PACKAGE.equals(context.getPackageName()));
        long until = SystemClock.elapsedRealtime() + (expected ? 8000 : 3000);
        do {
            boolean reachable = false;
            try (Socket socket = new Socket()) {
                socket.connect(new InetSocketAddress("10.0.2.2", 11940), 1000);
                socket.setSoTimeout(1000);
                socket.getOutputStream().write("BKCHECK!".getBytes(StandardCharsets.US_ASCII));
                byte[] reply = new byte[10];
                new DataInputStream(socket.getInputStream()).readFully(reply);
                reachable = Arrays.equals(reply, "BK-OUTSIDE".getBytes(StandardCharsets.US_ASCII));
            } catch (java.io.IOException unavailable) {
                // Expected in the retained TUN case.
            }
            if (expected && reachable) return;
            require(expected || !reachable);
            SystemClock.sleep(100);
        } while (SystemClock.elapsedRealtime() < until);
        require(!expected);
    }

    private static void require(boolean ok) {
        if (!ok) throw new AssertionError("Mihomo Android fixture contract");
    }
}
