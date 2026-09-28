package dz.nova.nova_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `nova/chime`: plays the device's default notification sound when a
 * notification arrives in realtime (the in-app banner's chime). Silent
 * and vibrate modes are respected: nothing plays unless the ringer is
 * normal, and Do Not Disturb mutes the notification usage as usual.
 */
object NotificationChime {
    private var current: Ringtone? = null

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "nova/chime").setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> result.success(play(appContext))
                else -> result.notImplemented()
            }
        }
    }

    private fun play(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        return try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return false
            val ringtone = RingtoneManager.getRingtone(context, uri) ?: return false
            ringtone.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            current?.stop()
            current = ringtone
            ringtone.play()
            true
        } catch (error: Exception) {
            false
        }
    }
}
