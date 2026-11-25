package com.blackoutkit.vpn

/**
 * Ownership is assigned before activation: a failed or partially started native
 * core must be closed before another core is admitted.
 */
internal class EmbeddedCoreOwner<T : Any>(
    private val close: (T) -> Unit,
) {
    @Volatile
    var current: T? = null
        private set

    @Volatile
    var running: Boolean = false
        private set

    @Synchronized
    fun start(
        create: () -> T?,
        activate: (T) -> Boolean,
    ): Boolean {
        stop()
        val created = create() ?: return false
        current = created
        try {
            running = activate(created)
            return running
        } finally {
            if (!running) stop()
        }
    }

    @Synchronized
    fun stop() {
        val owned = current ?: return
        running = false
        // Do not discard the handle when the native close fails.
        close(owned)
        current = null
    }
}

/**
 * gomobile newService/start/close and startLoop/stopLoop explicitly declare
 * checked java.lang.Exception. Translate that ABI at one boundary; do not
 * consume fatal JVM errors or include native diagnostics in user-facing text.
 */
internal fun <T> embeddedCall(block: () -> T): Result<T> =
    try {
        Result.success(block())
    } catch (failure: InterruptedException) {
        Thread.currentThread().interrupt()
        Result.failure(failure)
    } catch (failure: Exception) {
        Result.failure(failure)
    } catch (failure: LinkageError) {
        Result.failure(failure)
    }
