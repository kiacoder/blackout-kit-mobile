package com.blackoutkit.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.widget.Toast
import androidx.core.content.IntentCompat

/** Non-exported target of the status token given only to PackageInstaller. */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        val id = intent.data?.schemeSpecificPart?.toIntOrNull()
        val expectedAction = intent.action == ACTION_STATUS && intent.data?.scheme == "blackout-install"
        if (!expectedAction || id == null || id != intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)) {
            return
        }
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> confirm(context, id, intent)
            PackageInstaller.STATUS_SUCCESS -> finish(context, id, "Update installed.")
            PackageInstaller.STATUS_FAILURE_ABORTED -> finish(context, id, "Update cancelled.")
            else -> finish(context, id, "Update failed. Your existing app remains installed.")
        }
    }

    private fun confirm(
        context: Context,
        id: Int,
        status: Intent,
    ) {
        val confirmation = IntentCompat.getParcelableExtra(status, Intent.EXTRA_INTENT, Intent::class.java)
        if (confirmation == null) {
            finish(context, id, "Android did not provide update confirmation.")
        } else {
            UpdateConfirmation.offer(context, id, confirmation)
        }
    }

    private fun finish(
        context: Context,
        id: Int,
        message: String,
    ) {
        UpdateConfirmation.clear(context, id)
        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
    }

    companion object {
        internal const val ACTION_STATUS = "com.blackoutkit.vpn.UPDATE_INSTALL_STATUS"
    }
}
