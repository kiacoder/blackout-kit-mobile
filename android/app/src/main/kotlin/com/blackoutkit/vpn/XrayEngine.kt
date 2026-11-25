package com.blackoutkit.vpn

import android.content.Context
import android.util.Base64
import android.util.Log
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean

private const val XUDP_KEY_BYTES = 32

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

    /**
     * Fired when the core stops without [stop] being called — i.e. it crashed
     * or shut itself down. The service uses this to decide whether to hold the
     * TUN interface open (kill switch) or tear the tunnel down.
     */
    @Volatile
    var unexpectedStopListener: ((String) -> Unit)? = null

    private val envInitialized = AtomicBoolean(false)

    private val owner =
        EmbeddedCoreOwner<CoreController> { current ->
            stoppingIntentionally = true
            try {
                embeddedCall { current.stopLoop() }.getOrElse { failure ->
                    lastError = "Xray core cleanup failed; retry cleanup before starting another core"
                    Log.w(TAG, "Core stop failed: ${failure.javaClass.simpleName}")
                    error(lastError!!)
                }
            } finally {
                stoppingIntentionally = false
            }
        }

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
                    "The Xray core stopped unexpectedly",
                )
            }
            return 0
        }

        override fun onEmitStatus(
            code: Long,
            message: String?,
        ): Long {
            Log.i(TAG, "core status [$code]")
            return 0
        }
    }

    /** True when the core has been brought up and not yet torn down. */
    val isRunning: Boolean
        get() = owner.current?.isRunning == true

    internal val hasOwnedCore: Boolean get() = owner.current != null

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
        if (!GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.EMBEDDED)) {
            lastError = GoRuntimeAdmission.RESTART_REQUIRED
            return false
        }
        return envInitialized.get() ||
            synchronized(this) {
                envInitialized.get() || initializeEnvironment(context)
            }
    }

    private fun initializeEnvironment(context: Context): Boolean =
        try {
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
        } catch (t: LinkageError) {
            environmentFailure(t)
        } catch (t: IllegalStateException) {
            environmentFailure(t)
        } catch (t: SecurityException) {
            environmentFailure(t)
        } catch (t: ClassCastException) {
            environmentFailure(t)
        }

    private fun environmentFailure(failure: Throwable): Boolean {
        lastError = "Could not initialise the Xray core environment"
        Log.w(TAG, "Core environment failure: ${failure.javaClass.simpleName}")
        return false
    }

    /** Human-readable core version, or null if the AAR is missing. */
    fun version(): String? =
        try {
            if (GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.EMBEDDED)) {
                Libv2ray.checkVersionX()
            } else {
                null
            }
        } catch (t: LinkageError) {
            Log.w(TAG, "checkVersionX failed: ${t.javaClass.simpleName}")
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
    fun start(
        context: Context,
        configJson: String,
        tunFd: Int,
    ): Boolean {
        if (configJson.isBlank()) {
            lastError = "Refusing to start the Xray core with an empty config"
            Log.e(TAG, lastError!!)
            return false
        }
        return ensureEnv(context) && startInitializedCore(configJson, tunFd)
    }

    private fun startInitializedCore(
        configJson: String,
        tunFd: Int,
    ): Boolean =
        owner.start(
            create = {
                embeddedCall { Libv2ray.newCoreController(CoreCallback) }.getOrElse { failure ->
                    lastError = "Could not create the Xray core controller"
                    Log.w(TAG, "Core creation failed: ${failure.javaClass.simpleName}")
                    null
                }
            },
            activate = { created ->
                val started =
                    embeddedCall {
                        created.startLoop(configJson, tunFd)
                        created.isRunning
                    }.getOrElse { failure ->
                        Log.w(TAG, "Core startup failed: ${failure.javaClass.simpleName}")
                        false
                    }
                lastError = if (started) null else "Xray core rejected the configuration or failed to start"
                started
            },
        )

    /**
     * Starts the core in "no tunnel" mode so it can serve the loopback SOCKS
     * port only. Used by the connection tester, which probes a config without
     * touching the device's routing.
     */
    fun startProxyOnly(
        context: Context,
        configJson: String,
    ): Boolean = start(context, configJson, NO_TUN)

    /** Tears the core down. Safe to call when nothing is running. */
    fun stop() {
        owner.stop()
    }

    /** True when this device can actually run the bundled core. */
    fun isSupported(): Boolean = version() != null
}

/**
 * XUDP reads this setting as unpadded URL-safe Base64 and decodes it to a
 * 32-byte per-install key. URL-safe Base64 remains ASCII across gomobile's
 * Java-to-Go string conversion.
 */
private fun xudpBaseKey(context: Context): String {
    // Called under the initialization lock. Persist an independent random
    // key instead of deriving one from a device ID or a public fallback.
    val preferences = context.getSharedPreferences("xudp_private", Context.MODE_PRIVATE)
    val flags = Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP
    val existing = preferences.getString("base_key", null)
    if (existing != null) {
        val decoded =
            try {
                Base64.decode(existing, flags)
            } catch (_: IllegalArgumentException) {
                null
            }
        if (decoded?.size == XUDP_KEY_BYTES) return existing
    }
    val key = ByteArray(XUDP_KEY_BYTES).apply { SecureRandom().nextBytes(this) }
    val encoded = Base64.encodeToString(key, flags)
    check(preferences.edit().putString("base_key", encoded).commit()) {
        "Could not persist the XUDP installation key"
    }
    return encoded
}
