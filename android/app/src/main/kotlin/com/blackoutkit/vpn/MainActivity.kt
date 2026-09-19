package com.blackoutkit.vpn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The native tunnel bridge is not a pub package, so it is registered here
        // rather than by the generated plugin registrant.
        flutterEngine.plugins.add(VpnPlugin())
    }
}
