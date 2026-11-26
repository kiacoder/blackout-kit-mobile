package com.blackoutkit.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast

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
            PackageInstaller.STATUS_PENDING_USER_ACTION -> confirm(context, intent)
            PackageInstaller.STATUS_SUCCESS -> notify(context, "Update installed.")
            PackageInstaller.STATUS_FAILURE_ABORTED -> notify(context, "Update cancelled.")
            else -> notify(context, "Update failed. Your existing app remains installed.")
        }
    }

    @Suppress("DEPRECATION")
    private fun confirm(
        context: Context,
        status: Intent,
    ) {
        val confirmation =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                status.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                status.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
        if (confirmation == null) {
            notify(context, "Android did not provide update confirmation.")
            return
        }
        try {
            // Only the OS package installer may handle the confirmation.
            val target = context.packageManager.resolveActivity(confirmation, PackageManager.MATCH_SYSTEM_ONLY)
            if (target?.activityInfo == null) {
                notify(context, "Android update confirmation unavailable.")
            } else {
                confirmation.setClassName(target.activityInfo.packageName, target.activityInfo.name)
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirmation)
            }
        } catch (_: android.content.ActivityNotFoundException) {
            notify(context, "Android update confirmation unavailable.")
        } catch (_: SecurityException) {
            notify(context, "Android update confirmation denied.")
        }
    }

    private fun notify(
        context: Context,
        message: String,
    ) {
        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
    }

    companion object {
        internal const val ACTION_STATUS = "com.blackoutkit.vpn.UPDATE_INSTALL_STATUS"
    }
}
