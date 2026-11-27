package com.blackoutkit.vpn;

// Host JNI ABI smoke test; deliberately never opens a real network connection.
public final class OpenVpnNativeBridge {
    private native long nativeCreate();
    private native int nativeRun(long handle, Object callbacks, byte[] profile, byte[] user, byte[] password);
    private native void nativeCancel(long handle);
    private native boolean nativeRelease(long handle);

    public static final class Callbacks {
        public boolean reset() { throw new AssertionError("Unexpected TUN callback"); }
        public boolean address(String value, int prefix) { return false; }
        public boolean route(String value, int prefix) { return false; }
        public boolean dns(String value) { return false; }
        public boolean mtu(int value) { return false; }
        public boolean protect(int fd) { return false; }
        public int establish() { return -1; }
        public void connected(boolean value) { if (value) throw new AssertionError("False connected"); }
    }

    private static void require(boolean value) {
        if (!value) throw new AssertionError("JNI lifecycle contract");
    }

    public static void main(String[] args) {
        System.load(args[0]);
        OpenVpnNativeBridge api = new OpenVpnNativeBridge();
        byte[] empty = new byte[0];
        Callbacks cb = new Callbacks();
        long first = api.nativeCreate();
        require(first > 0);
        require(api.nativeCreate() == 0);
        require(!api.nativeRelease(first + 1));
        api.nativeCancel(first);
        require(api.nativeRun(first, cb, empty, empty, empty) != 0);
        require(api.nativeRun(first, cb, empty, empty, empty) != 0);
        require(api.nativeRelease(first));
        require(!api.nativeRelease(first));
        long second = api.nativeCreate();
        require(second > first);
        api.nativeCancel(first);
        require(api.nativeRun(first, cb, empty, empty, empty) != 0);
        require(api.nativeRun(second, cb, new byte[1048577], empty, empty) != 0);
        require(api.nativeRelease(second));
        long third = api.nativeCreate();
        require(api.nativeRun(third, new Object(), empty, empty, empty) != 0);
        require(api.nativeRelease(third));
        System.out.println("PASS host JNI single-owner, stale handle, cancellation, bounded input and callback failure");
    }
}
