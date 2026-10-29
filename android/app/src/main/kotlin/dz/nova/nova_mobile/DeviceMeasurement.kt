package dz.nova.nova_mobile

import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaDrm
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DummyExoMediaDrm
import androidx.media3.exoplayer.drm.ExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * D-168 phase 1a (`nova/measure`): what this phone can do with DRM, measured
 * once per app version by `lib/core/security/device_measurement.dart`.
 * Nothing here touches the Student's playback:
 *
 *  - `snapshot`      Widevine level and HDCP (MediaDrm), a secure H.264
 *                    decoder for 1080p, Google Play services and the Play
 *                    Store, model and Android version
 *  - `testPlayback`  a few seconds of the protected `/device-check` test
 *                    pattern with its real Axinom licence, muted, without a
 *                    view, in the phone's own Widevine level or forced to L3
 *                    (`forceL3`); answers `{result, error, code, decoder}`
 *  - `integrity`     a Play Integrity standard token bound to `requestHash`
 *                    (only when the server configured Play Integrity)
 */
object DeviceMeasurement {
    /** Our own `integrity` error codes, outside Play Integrity's (-1 … -100). */
    private const val INTEGRITY_BAD_ARGUMENTS = -902
    private const val INTEGRITY_UNKNOWN_ERROR = -901
    private const val INTEGRITY_TIMEOUT = -900

    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "nova/measure").setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> Thread {
                    val value = try {
                        snapshot(app)
                    } catch (error: Exception) {
                        emptyMap()
                    }
                    main.post { result.success(value) }
                }.start()
                "testPlayback" -> TestPlayback(app, call, result).start()
                "integrity" -> integrity(app, call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun snapshot(context: Context): Map<String, Any?> {
        val widevine = widevine()
        val (decoder1080p, decoder) = secureAvcDecoder()
        val gms = packageVersion(context, "com.google.android.gms")
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80),
            "osVersion" to (Build.VERSION.RELEASE ?: "").take(32),
            "sdkInt" to Build.VERSION.SDK_INT,
            "securityLevel" to widevine["securityLevel"],
            "maxHdcp" to widevine["maxHdcp"],
            "connectedHdcp" to widevine["connectedHdcp"],
            "secureDecoder1080p" to decoder1080p,
            "secureDecoder" to decoder,
            "googlePlayServices" to (gms != null),
            "gmsVersion" to gms,
            "playStore" to (packageVersion(context, "com.android.vending") != null),
        )
    }

    /** "L1" / "L3" and HDCP, or an empty map without Widevine. */
    private fun widevine(): Map<String, String?> {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(C.WIDEVINE_UUID)
            mapOf(
                "securityLevel" to drm.getPropertyString("securityLevel"),
                "maxHdcp" to hdcp(drm, max = true),
                "connectedHdcp" to hdcp(drm, max = false),
            )
        } catch (error: Exception) {
            emptyMap()
        } finally {
            close(drm)
        }
    }

    private fun hdcp(drm: MediaDrm, max: Boolean): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            when (if (max) drm.maxHdcpLevel else drm.connectedHdcpLevel) {
                MediaDrm.HDCP_NONE -> "none"
                MediaDrm.HDCP_V1 -> "1.x"
                MediaDrm.HDCP_V2 -> "2.0"
                MediaDrm.HDCP_V2_1 -> "2.1"
                MediaDrm.HDCP_V2_2 -> "2.2"
                6 -> "2.3" // MediaDrm.HDCP_V2_3 (Android 10)
                MediaDrm.HDCP_NO_DIGITAL_OUTPUT -> "no_output"
                else -> "unknown"
            }
        } else {
            // Widevine's own property before Android 9, e.g. "HDCP-2.2".
            drm.getPropertyString(if (max) "maxHdcpLevel" else "hdcpLevel")
                .lowercase()
                .removePrefix("hdcp-")
                .replace(Regex("[^a-z0-9._-]"), "_")
                .take(24)
                .ifEmpty { null }
        }
    } catch (error: Exception) {
        null
    }

    /**
     * Whether a secure (DRM) H.264 decoder plays 1080p30, and the first
     * secure H.264 decoder's name.
     */
    private fun secureAvcDecoder(): Pair<Boolean, String?> {
        var first: String? = null
        for (info in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
            if (info.isEncoder) continue
            val type = info.supportedTypes.firstOrNull { it.equals(MimeTypes.VIDEO_H264, ignoreCase = true) } ?: continue
            val capabilities = try {
                info.getCapabilitiesForType(type)
            } catch (error: Exception) {
                continue
            }
            if (!capabilities.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)) continue
            val name = info.name.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80)
            if (first == null) first = name
            if (capabilities.videoCapabilities?.areSizeAndRateSupported(1920, 1080, 30.0) == true) return true to name
        }
        return false to first
    }

    /** Version code of an installed, enabled package (Play services, Play Store). */
    private fun packageVersion(context: Context, name: String): Long? = try {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(name, 0)
        if (info.applicationInfo?.enabled == false) {
            null
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
    } catch (error: PackageManager.NameNotFoundException) {
        null
    }

    private fun integrity(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
        val hash = call.argument<String>("requestHash") ?: ""
        if (project == null || hash.isEmpty()) {
            result.success(mapOf("errorCode" to INTEGRITY_BAD_ARGUMENTS))
            return
        }
        var answered = false
        fun answer(value: Map<String, Any?>) = main.post {
            if (!answered) {
                answered = true
                result.success(value)
            }
        }
        main.postDelayed({ answer(mapOf("errorCode" to INTEGRITY_TIMEOUT)) }, 30_000)
        try {
            IntegrityManagerFactory.createStandard(context)
                .prepareIntegrityToken(PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build())
                .addOnSuccessListener { provider ->
                    provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                        .addOnSuccessListener { response -> answer(mapOf("token" to response.token())) }
                        .addOnFailureListener { error -> answer(mapOf("errorCode" to integrityCode(error))) }
                }
                .addOnFailureListener { error -> answer(mapOf("errorCode" to integrityCode(error))) }
        } catch (error: Exception) {
            answer(mapOf("errorCode" to INTEGRITY_UNKNOWN_ERROR))
        }
    }

    /**
     * The Play Integrity error code (`StandardIntegrityErrorCode`, e.g. -2
     * no Play Store), read without depending on the exception's class.
     */
    private fun integrityCode(error: Exception): Int {
        for (getter in listOf("getErrorCode", "getStatusCode")) {
            val code = runCatching { error.javaClass.getMethod(getter).invoke(error) as? Int }.getOrNull()
            if (code != null) return code
        }
        return Regex("""\((-?\d+)\)""").find(error.message ?: "")?.groupValues?.get(1)?.toIntOrNull()
            ?: INTEGRITY_UNKNOWN_ERROR
    }

    /**
     * A lesson, Replay or Live player is about to start: a running test
     * playback stops at once (`inconclusive` / `interrupted`, measured again
     * later) so it never holds the phone's only secure decoder.
     */
    fun interruptTest() {
        if (Looper.myLooper() == Looper.getMainLooper()) TestPlayback.interrupt() else main.post { TestPlayback.interrupt() }
    }

    internal fun close(drm: MediaDrm?) {
        if (drm == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) drm.close() else @Suppress("DEPRECATION") drm.release()
    }
}

/**
 * One measured playback of the test pattern: Media3 with Widevine, no
 * surface (Media3 decodes to its own placeholder surface, a secure one for
 * L1), volume 0 and no audio focus (another app's sound goes on), at most
 * 480p. `passed` once the licence keys are loaded, a video decoder decoded
 * frames and 3 s were played; `failed` on a player error (same categories as
 * the lesson player); `inconclusive` when the keys loaded but no decoded
 * picture could be confirmed, or when a real player started meanwhile.
 */
@OptIn(UnstableApi::class)
private class TestPlayback(
    private val context: Context,
    call: MethodCall,
    private val result: MethodChannel.Result,
) {
    private val manifest = call.argument<String>("manifest") ?: ""
    private val license = call.argument<String>("license") ?: ""
    private val token = call.argument<String>("token") ?: ""
    private val forceL3 = call.argument<Boolean>("forceL3") == true
    private val timeoutMs = (call.argument<Number>("timeoutMs") ?: 30_000).toLong().coerceIn(5_000, 60_000)
    private val main = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var keysLoaded = false
    private var decoder: String? = null
    private var done = false

    private val poll = object : Runnable {
        override fun run() {
            val exo = player ?: return
            if (done) return
            if (keysLoaded && exo.currentPosition >= PLAYED_MS) {
                val counters = exo.videoDecoderCounters
                counters?.ensureUpdated()
                val frames = (counters?.renderedOutputBufferCount ?: 0) + (counters?.skippedOutputBufferCount ?: 0) +
                    (counters?.droppedBufferCount ?: 0)
                if (decoder != null && frames > 0) finish("passed") else finish("inconclusive", "no_video_decoder")
                return
            }
            main.postDelayed(this, 500)
        }
    }

    private val timeout = Runnable {
        finish(if (keysLoaded) "inconclusive" else "failed", "timeout")
    }

    fun start() {
        if (manifest.isEmpty() || license.isEmpty()) return finish("unavailable", "no_test_video")
        if (forceL3 && !canForceL3()) return finish("unavailable", "l3_not_forceable")
        current?.finish("inconclusive", "interrupted")
        current = this
        try {
            val http = DefaultHttpDataSource.Factory()
            val callback = HttpMediaDrmCallback(license, http)
            callback.setKeyRequestProperty("X-AxDRM-Message", token)
            val drm = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID, if (forceL3) L3_PROVIDER else FrameworkMediaDrm.DEFAULT_PROVIDER)
                .build(callback)
            val item = MediaItem.Builder().setUri(manifest).setMimeType(MimeTypes.APPLICATION_MPD).build()
            val source = DashMediaSource.Factory(http).setDrmSessionManagerProvider { drm }.createMediaSource(item)
            val exo = ExoPlayer.Builder(context).build()
            player = exo
            exo.volume = 0f
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                .setMaxVideoSize(Int.MAX_VALUE, MAX_HEIGHT)
                .build()
            exo.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    main.post { finish("failed", playbackCategory(error), error.errorCode) }
                }
            })
            exo.addAnalyticsListener(object : AnalyticsListener {
                override fun onDrmKeysLoaded(eventTime: AnalyticsListener.EventTime) {
                    keysLoaded = true
                }

                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    decoder = decoderName
                }
            })
            exo.setMediaSource(source)
            exo.prepare()
            exo.playWhenReady = true
            main.postDelayed(poll, 500)
            main.postDelayed(timeout, timeoutMs)
        } catch (error: Exception) {
            finish("failed", "drm_init")
        }
    }

    /** Whether this phone lets an app open Widevine in L3 (also an L1 phone). */
    private fun canForceL3(): Boolean {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(C.WIDEVINE_UUID)
            drm.setPropertyString("securityLevel", "L3")
            true
        } catch (error: Exception) {
            false
        } finally {
            DeviceMeasurement.close(drm)
        }
    }

    private fun finish(outcome: String, error: String? = null, code: Int? = null) {
        if (done) return
        done = true
        if (current === this) current = null
        main.removeCallbacks(poll)
        main.removeCallbacks(timeout)
        player?.release()
        player = null
        result.success(mapOf("result" to outcome, "error" to error, "code" to code, "decoder" to decoder))
    }

    companion object {
        private const val PLAYED_MS = 3_000L
        private const val MAX_HEIGHT = 480

        /** The running test (main thread only). */
        private var current: TestPlayback? = null

        fun interrupt() {
            current?.finish("inconclusive", "interrupted")
        }

        /** Widevine opened in software (L3): the property is set before any session. */
        private val L3_PROVIDER = ExoMediaDrm.Provider { uuid ->
            try {
                val drm = FrameworkMediaDrm.newInstance(uuid)
                try {
                    drm.setPropertyString("securityLevel", "L3")
                    drm
                } catch (error: Exception) {
                    drm.release()
                    DummyExoMediaDrm()
                }
            } catch (error: Exception) {
                DummyExoMediaDrm()
            }
        }
    }
}
