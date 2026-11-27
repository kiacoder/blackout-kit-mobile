package com.blackoutkit.vpn;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;

/** Private Android load and ownership smoke test. Does not create a VPN. */
public final class OpenVpnCandidateAcceptance extends Instrumentation {
    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            require("com.blackoutkit.vpn.openvpntest".equals(getTargetContext().getPackageName()));
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
            result.putString("stream", "\nOPENVPN_CANDIDATE_LOAD_PASS\n");
            finish(Activity.RESULT_OK, result);
        } catch (Exception | LinkageError | AssertionError failure) {
            result.putString("stream", "\nOPENVPN_CANDIDATE_LOAD_FAIL\n");
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static void require(boolean value) {
        if (!value) throw new AssertionError("OpenVPN native contract");
    }
}
