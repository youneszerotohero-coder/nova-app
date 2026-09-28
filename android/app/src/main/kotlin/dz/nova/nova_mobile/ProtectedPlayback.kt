package dz.nova.nova_mobile

import android.content.Context
import android.media.MediaDrm
import android.os.Build
import androidx.media3.common.C
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Registers the protected player view (`nova/protected-player`) and the
 * DRM capability channel (`nova/drm`).
 */
object ProtectedPlayback {
    fun register(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        engine.platformViewsController.registry.registerViewFactory(
            "nova/protected-player",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    @Suppress("UNCHECKED_CAST")
                    val params = args as? Map<String, Any?> ?: emptyMap()
                    return ProtectedPlayerView(context, messenger, viewId, params)
                }
            },
        )
        MethodChannel(messenger, "nova/drm").setMethodCallHandler { call, result ->
            when (call.method) {
                "widevineLevel" -> result.success(widevineLevel())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * "L1" (hardware, TEE-backed), "L3" (software) or null without
     * Widevine. The backend's strict policy licenses L1 only, exactly as
     * the web player refuses a software-only CDM.
     */
    private fun widevineLevel(): String? {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(C.WIDEVINE_UUID)
            drm.getPropertyString("securityLevel")
        } catch (error: Exception) {
            null
        } finally {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) drm?.close() else @Suppress("DEPRECATION") drm?.release()
        }
    }
}
