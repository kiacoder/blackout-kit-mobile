package com.blackoutkit.vpn

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * In-process wrapper around the bundled Xray core (libv2ray /
 * AndroidLibXrayLite, gomobile-bound).
 *
 * ## Why in-process instead of a subprocess
 *
 * Android API 29+ refuses to `exec()` anything that is not inside the app's
 * `nativeLibraryDir`, and even there it is fragile. Rather than ship a
 * `libxray.so` plus a separate tun2socks and hope both launch, the core is
 * linked straight into the app process through the AAR in `app/libs`.
 *
 * ## Why there is no tun2socks here
 *
 * Xray has a native `tun` inbound. [CoreController.startLoop] writes the file
 * descriptor into the `xray.tun.fd` environment variable and Xray then reads
 * packets off it directly, running its own netstack. So the data path is:
 *
 *     device traffic -> VpnService TUN fd -> Xray tun inbound -> Xray outbound
 *
 * No SOCKS hop, no userspace bridge, one less thing to break. tun2socks is only
 * needed for engines that *cannot* bind a TUN themselves (see [EngineRunner]).
 *
 * ## Verification
 *
 * The API used below was read off the shipped `classes.jar` with `javap`, not
 * guessed:
 *
 *     libv2ray.Libv2ray.newCoreController(CoreCallbackHandler) -> CoreController
 *     libv2ray.Libv2ray.initCoreEnv(String, String)
 *     libv2ray.CoreController.startLoop(String, int) throws Exception
 *     libv2ray.CoreController.stopLoop() throws Exception
 *     interface CoreCallbackHandler { long onEmitStatus(long, String); long shutdown(); long startup(); }
 */
object XrayEngine {

    private const val TAG = "BlackoutXrayEngine"

    /** `tunFd == 0` means "do not use TUN" on the native side. */
    private const val NO_TUN = 0

    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    var lastConfigJson: String? = null
        private set

    /**
     * Fired when the core stops without [stop] being called — i.e. it crashed
     * or shut itself down. The service uses this to decide whether to hold the
     * TUN interface open (kill switch) or tear the tunnel down.
     */
    @Volatile
    var unexpectedStopListener: ((String) -> Unit)? = null

    private val envInitialized = AtomicBoolean(false)

    // Written from the establish worker thread, cleared from the main thread
    // (teardown / onRevoke / onDestroy). Without @Volatile the main thread can
    // observe a stale null and skip stopLoop(), leaving the core running
    // against a closed TUN fd.
    @Volatile
    private var controller: CoreController? = null

    /** Set immediately before an intentional stop so the callback can tell the difference. */
    @Volatile
    private var stoppingIntentionally = false

    /**
     * Callback used to surface core lifecycle events into the log.
     *
     * Deliberately does not push a "connected" status to Dart: `startup()` fires
     * from inside `startLoop()`, i.e. before the service has confirmed the
     * tunnel is usable. The service owns that transition.
     */
    private object CoreCallback : CoreCallbackHandler {
        override fun startup(): Long {
            Log.i(TAG, "core startup")
            return 0
        }

        override fun shutdown(): Long {
            Log.i(TAG, "core shutdown")
            if (!stoppingIntentionally) {
                Log.e(TAG, "core stopped without being asked to - treating as a failure")
                unexpectedStopListener?.invoke(
                    "The Xray core stopped unexpectedly"
                )
            }
            return 0
        }

        override fun onEmitStatus(code: Long, message: String?): Long {
            Log.i(TAG, "core status [$code] $message")
            return 0
        }
    }

    /** True when the core has been brought up and not yet torn down. */
    val isRunning: Boolean
        get() = controller?.isRunning == true

    /**
     * One-time environment setup.
     *
     * `Seq.setContext` is mandatory: the Go asset reader (`golang.org/x/mobile/
     * asset`) needs an `AssetManager` to fall back to when a file is not on
     * disk. Without it, any asset-backed lookup fails with a bare "no such
     * file" from inside the Go runtime.
     *
     * ## Geo data is deliberately *not* shipped
     *
     * `libv2ray.aar` bundles `geoip.dat`, `geosite.dat` and
     * `geoip-only-cn-private.dat` (~28 MB uncompressed, ~7.5 MB deflated), but
     * `androidResources.ignoreAssetsPattern` in `app/build.gradle` strips all
     * three from the APK to keep the download small. Do not describe them as
     * available at runtime.
     *
     * Consequence: routing rules that reference `geosite:` or `geoip:` tags
     * cannot resolve and the core logs `ignore invalid geosite entry` /
     * falls back to a non-match. [XrayConfigBuilder] therefore never emits
     * geo-tagged rules — split tunneling is expressed as explicit CIDRs and
     * domains instead. If geo routing is ever wanted, drop the three
     * `!geo*.dat` entries from `ignoreAssetsPattern` first.
     */
    private fun ensureEnv(context: Context): Boolean {
        if (envInitialized.get()) return true
        synchronized(this) {
            if (envInitialized.get()) return true
            return try {
                Seq.setContext(context.applicationContext)
                // First argument becomes `xray.location.asset` — the on-disk
                // root the geodata loader probes before falling back to the
                // AssetManager set above. filesDir is normally empty of geo
                // files, so the fallback is what would serve them; see the
                // note above on why nothing does today.
                // Second argument becomes `xray.xudp.basekey`.
                Libv2ray.initCoreEnv(context.filesDir.absolutePath, xudpBaseKey(context))
                envInitialized.set(true)
                Log.i(TAG, "core env initialised, ${version()}")
                true
            } catch (t: Throwable) {
                lastError = "Could not initialise the Xray core environment: ${t.message}"
                Log.e(TAG, lastError, t)
                false
            }
        }
    }

    /**
     * XUDP needs a per-install 32-byte key.
     *
     * The core reads this env value AS the key itself and requires exactly
     * 32 BYTES. Two constraints shape how the bytes travel:
     *  - base64 text is wrong (44 chars ≠ 32 bytes — the first attempt);
     *  - raw bytes > 0x7F are wrong too: the gomobile JNI bridge re-encodes
     *    Java strings to UTF-8, so high bytes become multi-byte sequences
     *    and the core ends up with a mangled, miscounted key ("len 0" — the
     *    second attempt).
     * The safe corridor is exactly 32 bytes, each in 0x01–0x7F: single-byte
     * UTF-8 everywhere, so the byte count survives the Java→Go trip intact.
     * Each digest byte is masked to 7 bits and 0x00 is lifted to 0x01.
     */
    private fun xudpBaseKey(context: Context): String {
        val seed = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ANDROID_ID
            )
        } catch (t: Throwable) {
            null
        } ?: "blackout-kit"
        val digest = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
        val safe = ByteArray(32) { i ->
            val b = (digest[i].toInt() and 0x7F)
            (if (b == 0) 0x01 else b).toByte()
        }
        return String(safe, Charsets.US_ASCII)
    }

    /** Human-readable core version, or null if the AAR is missing. */
    fun version(): String? = try {
        Libv2ray.checkVersionX()
    } catch (t: Throwable) {
        Log.w(TAG, "checkVersionX failed: ${t.message}")
        null
    }

    /**
     * Starts the core against [tunFd].
     *
     * [configJson] must already contain a `tun` protocol inbound — the fd is
     * only exported through the `xray.tun.fd` environment variable, and Xray
     * still has to be told to bind it. See [com.blackoutkit.vpn] `XrayConfig`.
     *
     * @return true only when the core is genuinely running. Callers must not
     *   report a successful connection otherwise: the default route is already
     *   installed by the time this returns, so a false positive black-holes all
     *   traffic on the device.
     */
    fun start(context: Context, configJson: String, tunFd: Int): Boolean {
        if (configJson.isBlank()) {
            lastError = "Refusing to start the Xray core with an empty config"
            Log.e(TAG, lastError!!)
            return false
        }
        if (!ensureEnv(context)) return false

        stop()

        return try {
            val created = Libv2ray.newCoreController(CoreCallback)
            lastConfigJson = configJson
            created.startLoop(configJson, tunFd)

            if (!created.isRunning) {
                // A half-started controller must be stopped explicitly —
                // leaving it unassigned means teardown() has no handle and
                // the native core keeps running with nobody owning it.
                try {
                    created.stopLoop()
                } catch (t: Throwable) {
                    Log.w(TAG, "stopLoop after failed start: ${t.message}")
                }
                lastError = "Xray core reported that it failed to start"
                Log.e(TAG, lastError!!)
                return false
            }

            controller = created
            lastError = null
            Log.i(TAG, "core running, tunFd=$tunFd")
            true
        } catch (t: Throwable) {
            // A config parse error surfaces here as an exception from
            // startLoop; the message is the most useful thing we can show.
            lastError = "Xray core rejected the configuration: ${t.message}"
            Log.e(TAG, lastError, t)
            false
        }
    }

    /**
     * Starts the core in "no tunnel" mode so it can serve the loopback SOCKS
     * port only. Used by the connection tester, which probes a config without
     * touching the device's routing.
     */
    fun startProxyOnly(context: Context, configJson: String): Boolean =
        start(context, configJson, NO_TUN)

    /** Tears the core down. Safe to call when nothing is running. */
    fun stop() {
        synchronized(this) {
            val current = controller ?: return
            controller = null
            stoppingIntentionally = true
            try {
                current.stopLoop()
                Log.i(TAG, "core stopped")
            } catch (t: Throwable) {
                Log.w(TAG, "error stopping core: ${t.message}")
            } finally {
                stoppingIntentionally = false
            }
        }
    }

    /** True when this device can actually run the bundled core. */
    fun isSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && version() != null
}
