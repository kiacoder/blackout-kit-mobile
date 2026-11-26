package com.blackoutkit.vpn

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import androidx.core.net.toUri
import java.io.File
import java.io.IOException

internal class ActiveUpdateSessionException : IllegalStateException("An update session is already active")

/** Stages verified bytes with the platform installer; never requests silent installation. */
internal class UpdateSessionInstaller(
    private val context: Context,
) {
    private val installer = context.packageManager.packageInstaller

    fun submit(
        file: File,
        expectedBytes: Long,
        expectedDigest: String,
    ) {
        // This runs only after a new explicit install request and verification.
        // Clear inactive sessions left by an interrupted previous staging attempt;
        // never disturb a session the platform is actively processing.
        val previous = installer.mySessions.filter { it.appPackageName == context.packageName }
        if (previous.any { it.isActive }) throw ActiveUpdateSessionException()
        previous.forEach { installer.abandonSession(it.sessionId) }
        val params =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(context.packageName)
                setSize(expectedBytes)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                }
            }
        val id = installer.createSession(params)
        var committed = false
        try {
            installer.openSession(id).use { session ->
                stage(session, file, expectedBytes, expectedDigest)
                val callback = statusCallback(id)
                session.commit(callback.intentSender)
                committed = true
            }
        } finally {
            if (!committed) abandon(id)
        }
    }

    /** Only called by an explicit user cancellation action. */
    fun cancelPending() {
        installer.mySessions
            .filter { it.appPackageName == context.packageName }
            .forEach { installer.abandonSession(it.sessionId) }
    }

    private fun stage(
        session: PackageInstaller.Session,
        file: File,
        expectedBytes: Long,
        expectedDigest: String,
    ) {
        session.openWrite("base.apk", 0, expectedBytes).use { output ->
            val verified =
                file.inputStream().use { input ->
                    VerifiedApkStream.copy(input, output, expectedBytes, expectedDigest)
                }
            if (!verified) throw IOException("APK changed during session staging")
            session.fsync(output)
        }
    }

    private fun statusCallback(id: Int): PendingIntent {
        val intent =
            Intent(context, UpdateInstallReceiver::class.java)
                .setAction(UpdateInstallReceiver.ACTION_STATUS)
                .setData("blackout-install:$id".toUri())
        // PackageInstaller fills in status extras. The mutable token has an
        // explicit private receiver, fixed action/data and unique session ID.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(context, id, intent, flags or PendingIntent.FLAG_CANCEL_CURRENT)
    }

    private fun abandon(id: Int) {
        try {
            installer.abandonSession(id)
        } catch (_: SecurityException) {
            Log.w("UpdateSession", "Session cleanup denied")
        } catch (_: IllegalArgumentException) {
            Log.w("UpdateSession", "Session already closed")
        }
    }
}
