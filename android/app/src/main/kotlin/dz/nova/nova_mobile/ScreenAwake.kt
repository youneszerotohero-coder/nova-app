package dz.nova.nova_mobile

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * D-133: `nova/screen` keeps the screen on while a video plays, as YouTube
 * does. Dart holds it while a lesson or Live picture moves and releases it on
 * pause, end or exit; the phone's normal sleep timer then applies again.
 * `FLAG_KEEP_SCREEN_ON` only acts while the window is visible.
 */
object ScreenAwake {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "nova/screen").setMethodCallHandler { call, result ->
            if (call.method != "keepOn") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val on = call.arguments == true
            activity.runOnUiThread {
                if (on) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
            result.success(null)
        }
    }
}
