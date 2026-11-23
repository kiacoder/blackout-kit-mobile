package com.blackoutkit.vpn

import java.util.concurrent.atomic.AtomicReference

/** Lock-free one-shot callback holder for cross-thread Android lifecycle edges. */
internal class OneShotCallbackSlot<T> {
    private val ref = AtomicReference<((T) -> Unit)?>(null)

    var value: ((T) -> Unit)?
        get() = ref.get()
        set(next) { ref.set(next) }

    fun take(): ((T) -> Unit)? = ref.getAndSet(null)

    /** Clear only the callback the caller previously captured. */
    fun clear(expected: ((T) -> Unit)?): Boolean =
        expected != null && ref.compareAndSet(expected, null)
}
