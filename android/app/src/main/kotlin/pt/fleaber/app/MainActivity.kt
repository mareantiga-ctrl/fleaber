package pt.fleaber.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal de alertas Fleaber (alta importância) + notificação local em foreground.
 * FCM em background/fechada usa o mesmo channel via meta-data no Manifest.
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CHANNEL_ID = "fleaber_alerts"
        const val CHANNEL_NAME = "Alertas Fleaber"
        private const val METHOD_CHANNEL = "pt.fleaber.app/push_ui"
        private const val EXTRA_CHAT = "fleaber_push_chat_id"
        private const val EXTRA_KIND = "fleaber_push_kind"
        private const val EXTRA_NID = "fleaber_push_notification_id"
    }

    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        ensureAlertChannel()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureChannel" -> {
                        ensureAlertChannel()
                        result.success(mapOf("channel_id" to CHANNEL_ID, "ok" to true))
                    }
                    "showLocal" -> {
                        val title = call.argument<String>("title") ?: "Fleaber"
                        val body = call.argument<String>("body") ?: ""
                        val chatId = call.argument<String>("chat_id") ?: ""
                        val kind = call.argument<String>("kind") ?: ""
                        val notificationId = call.argument<String>("notification_id") ?: ""
                        showLocalNotification(title, body, chatId, kind, notificationId)
                        result.success(true)
                    }
                    "consumeLaunchPush" -> {
                        result.success(extractPushExtras(intent))
                        // one-shot: clear so we don't re-open on rotate
                        intent?.removeExtra(EXTRA_CHAT)
                        intent?.removeExtra(EXTRA_KIND)
                        intent?.removeExtra(EXTRA_NID)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val extras = extractPushExtras(intent)
        if (extras != null) {
            methodChannel?.invokeMethod("onPushTap", extras)
            intent.removeExtra(EXTRA_CHAT)
            intent.removeExtra(EXTRA_KIND)
            intent.removeExtra(EXTRA_NID)
        }
    }

    private fun extractPushExtras(src: Intent?): Map<String, String>? {
        if (src == null) return null
        val chat = src.getStringExtra(EXTRA_CHAT)?.trim().orEmpty()
        val kind = src.getStringExtra(EXTRA_KIND)?.trim().orEmpty()
        val nid = src.getStringExtra(EXTRA_NID)?.trim().orEmpty()
        if (chat.isEmpty() && kind.isEmpty() && nid.isEmpty()) return null
        return mapOf(
            "chat_id" to chat,
            "kind" to kind,
            "notification_id" to nid,
        )
    }

    private fun ensureAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = mgr.getNotificationChannel(CHANNEL_ID)
        if (existing != null && existing.importance >= NotificationManager.IMPORTANCE_HIGH) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Mensagens, propostas e actualizações Fleaber"
            enableVibration(true)
            setShowBadge(true)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun showLocalNotification(
        title: String,
        body: String,
        chatId: String,
        kind: String,
        notificationId: String,
    ) {
        ensureAlertChannel()
        val launch = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT, chatId)
            putExtra(EXTRA_KIND, kind)
            putExtra(EXTRA_NID, notificationId)
        }
        val req = (System.currentTimeMillis() and 0x7fffffff).toInt()
        val pending = PendingIntent.getActivity(
            this,
            req,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        val id = (notificationId.ifEmpty { "$chatId|$kind" }.hashCode() and 0x7fffffff)
            .let { if (it == 0) req else it }
        NotificationManagerCompat.from(this).notify(id, notif)
    }
}
