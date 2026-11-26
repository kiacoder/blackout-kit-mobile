package com.blackoutkit.vpn

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.lang.ref.WeakReference

/** Main-thread-only handoff of the trusted platform confirmation to the resumed UI. */
internal object UpdateConfirmation {
    private const val CHANNEL_ID = "update_confirmation"
    private const val NOTIFICATION_ID = 9201
    private var foreground = WeakReference<Activity>(null)
    private var pending: Pair<Int, Intent>? = null

    fun attach(activity: MainActivity) {
        activity.lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onResume(owner: LifecycleOwner) {
                    foreground = WeakReference(activity)
                    launchIfResumed()
                }

                override fun onPause(owner: LifecycleOwner) {
                    if (foreground.get() === activity) foreground.clear()
                }
            },
        )
    }

    fun offer(
        context: Context,
        sessionId: Int,
        confirmation: Intent,
    ) {
        val session = context.packageManager.packageInstaller.getSessionInfo(sessionId)
        if (session?.appPackageName != context.packageName) return
        val target =
            context.packageManager
                .resolveActivity(
                    confirmation,
                    PackageManager.MATCH_SYSTEM_ONLY,
                )?.activityInfo
        if (target == null) {
            Toast.makeText(context, "Android update confirmation unavailable.", Toast.LENGTH_LONG).show()
            return
        }
        confirmation.setClassName(target.packageName, target.name)
        pending = sessionId to confirmation
        if (foreground.get() != null) {
            launchIfResumed()
        } else {
            remind(context)
        }
    }

    fun clear(
        context: Context,
        sessionId: Int,
    ) {
        if (pending?.first == sessionId) {
            pending = null
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        }
    }

    private fun launchIfResumed() {
        val activity = foreground.get() ?: return
        val (id, confirmation) = pending ?: return
        clear(activity, id)
        try {
            val session = activity.packageManager.packageInstaller.getSessionInfo(id)
            if (session?.appPackageName == activity.packageName) activity.startActivity(confirmation)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(activity, "Android update confirmation unavailable.", Toast.LENGTH_LONG).show()
        } catch (_: SecurityException) {
            Toast.makeText(activity, "Android update confirmation denied.", Toast.LENGTH_LONG).show()
        }
    }

    private fun remind(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled() ||
            (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
            )
        ) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                android.app.NotificationChannel(
                    CHANNEL_ID,
                    "App updates",
                    android.app.NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open =
            PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_vpn_notification)
                .setContentTitle("Blackout Kit update")
                .setContentText("Return to Blackout Kit to confirm installation.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notification permission is optional; resuming the app still works.
        }
    }
}
