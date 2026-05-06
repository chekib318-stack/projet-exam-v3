package tn.gov.education.examguard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground Service — runs BLE scan without Android's 30-second throttle.
 * Android exempts foreground services from background scan restrictions.
 * The service is started/stopped by Flutter via MethodChannel in MainActivity.
 */
class BleService : Service() {

    companion object {
        const val CHANNEL_ID      = "examguard_ble_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START    = "START_BLE_SCAN"
        const val ACTION_STOP     = "STOP_BLE_SCAN"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        // START_STICKY: system restarts service if killed, keeping scan alive
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ExamGuard — المسح نشط")
            .setContentText("جارٍ رصد الأجهزة الإلكترونية في القاعة")
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setContentIntent(openApp)
            .setOngoing(true)        // cannot be dismissed by user
            .setSilent(true)         // no sound for this notification
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ExamGuard BLE Scan",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "مسح Bluetooth النشط للكشف عن الأجهزة"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
