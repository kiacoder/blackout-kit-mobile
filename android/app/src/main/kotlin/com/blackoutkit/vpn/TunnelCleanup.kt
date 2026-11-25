package com.blackoutkit.vpn

/**
 * All engines receive a stop attempt. Descriptor release is conditional on
 * every stop succeeding; a native core may still reference the descriptor.
 */
internal fun stopEnginesBeforeRelease(
    stops: List<() -> Unit>,
    release: () -> Unit,
): Boolean {
    var stopped = true
    for (stop in stops) {
        try {
            stop()
        } catch (_: Exception) {
            stopped = false
        } catch (_: LinkageError) {
            stopped = false
        }
    }
    if (stopped) release()
    return stopped
}
