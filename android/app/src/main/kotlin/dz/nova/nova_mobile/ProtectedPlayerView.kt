package dz.nova.nova_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.hls.HlsMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * One playback (lesson, live or replay — D-067): Media3 ExoPlayer on a
 * secure SurfaceView, with Widevine or, for the D-070 clear copy, plain
 * adaptive HLS. Creation params come from the backend's authorization:
 *
 *  - `manifest`  signed DASH manifest URL, or the clear HLS manifest
 *  - `clear`     true for the clear copy: HLS, no DRM, automatic ABR;
 *                FLAG_SECURE, the secure surface and the watermark stay
 *  - `license`   Axinom Widevine licence URL (protected only)
 *  - `token`     Axinom entitlement, sent as `X-AxDRM-Message` on every
 *                licence request (same header as the web Shaka player)
 *  - `startMs`   resume position (VOD only)
 *  - `maxHeight` resolution cap from `protection.max_height`, or null
 *  - `live`      true for a Live: joins at the live edge, 12 s behind,
 *                catching up at up to 1.08× (web Shaka live tuning)
 *
 * The licence callback is kept so a Live can swap in a renewed
 * entitlement (`renewToken`) without reloading the stream, exactly as
 * the web player does.
 *
 * Control arrives on `nova/protected_player_<id>`, state leaves on
 * `nova/protected_player_<id>/events`.
 */
@OptIn(UnstableApi::class)
class ProtectedPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    params: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val surface = SurfaceView(context).apply {
        // Secure surface: protected frames never reach screenshots,
        // recordings or non-secure displays, independently of FLAG_SECURE.
        setSecure(true)
    }
    private val player: ExoPlayer = ExoPlayer.Builder(context).build()
    private val http = DefaultHttpDataSource.Factory()
    private val clear = params["clear"] == true
    private val licence: HttpMediaDrmCallback? =
        if (clear) null else HttpMediaDrmCallback(params["license"] as String, http)
    private val methods = MethodChannel(messenger, "nova/protected_player_$id")
    private val events = EventChannel(messenger, "nova/protected_player_$id/events")
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var released = false

    /** HTTP status of the last licence exchange (telemetry `license_status`). */
    private var licenseStatus = 0

    private val ticker = object : Runnable {
        override fun run() {
            if (released) return
            emit(
                mapOf(
                    "event" to "position",
                    "position" to player.currentPosition,
                    "duration" to player.duration.coerceAtLeast(0),
                    "buffered" to player.bufferedPosition,
                    "liveOffset" to player.currentLiveOffset.let { if (it == C.TIME_UNSET) -1L else it },
                ),
            )
            main.postDelayed(this, 500)
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        player.setVideoSurfaceView(surface)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                emit(
                    mapOf(
                        "event" to "state",
                        "state" to when (state) {
                            Player.STATE_BUFFERING -> "buffering"
                            Player.STATE_READY -> "ready"
                            Player.STATE_ENDED -> "ended"
                            else -> "idle"
                        },
                    ),
                )
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                emit(mapOf("event" to "playing", "value" to isPlaying))
            }

            override fun onRenderedFirstFrame() {
                emit(mapOf("event" to "firstFrame"))
            }

            override fun onTracksChanged(tracks: Tracks) {
                emit(mapOf("event" to "tracks", "heights" to videoHeights(tracks)))
            }

            override fun onPlayerError(error: PlaybackException) {
                licenseStatus = licenceHttpStatus(error) ?: licenseStatus
                emit(
                    mapOf(
                        "event" to "error",
                        "category" to category(error),
                        "kind" to kind(error),
                        "code" to error.errorCode,
                        "licenseStatus" to licenseStatus,
                        "message" to error.errorCodeName,
                    ),
                )
            }
        })
        player.addAnalyticsListener(object : AnalyticsListener {
            override fun onDrmKeysLoaded(eventTime: AnalyticsListener.EventTime) {
                licenseStatus = 200
            }
        })
        load(params)
    }

    private fun load(params: Map<String, Any?>) {
        val manifest = params["manifest"] as String
        val live = params["live"] == true
        val startMs = (params["startMs"] as? Number)?.toLong() ?: 0L
        val maxHeight = (params["maxHeight"] as? Number)?.toInt()

        licence?.setKeyRequestProperty("X-AxDRM-Message", params["token"] as? String ?: "")
        if (maxHeight != null) {
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setMaxVideoSize(Int.MAX_VALUE, maxHeight)
                .build()
        }

        val item = MediaItem.Builder()
            .setUri(manifest)
            .setMimeType(if (clear) MimeTypes.APPLICATION_M3U8 else MimeTypes.APPLICATION_MPD)
            .apply {
                if (live) {
                    setLiveConfiguration(
                        MediaItem.LiveConfiguration.Builder()
                            .setTargetOffsetMs(12_000)
                            .setMinPlaybackSpeed(1.0f)
                            .setMaxPlaybackSpeed(1.08f)
                            .build(),
                    )
                }
            }
            .build()
        // The clear copy has no DRM configuration at all: no MediaDrm session is
        // opened, so a device whose secure decoder failed plays it on the normal
        // decoders. Quality stays automatic (ABR) unless the Student picks one.
        val source = if (licence == null) {
            HlsMediaSource.Factory(http).createMediaSource(item)
        } else {
            val drm = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .build(licence)
            DashMediaSource.Factory(http)
                .setDrmSessionManagerProvider { drm }
                .createMediaSource(item)
        }

        if (live) player.setMediaSource(source) else player.setMediaSource(source, startMs)
        player.prepare()
        player.playWhenReady = true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (released) {
            result.success(null)
            return
        }
        when (call.method) {
            "play" -> player.play()
            "pause" -> player.pause()
            "seekTo" -> player.seekTo((call.argument<Number>("ms") ?: 0).toLong())
            "seekToLiveEdge" -> player.seekToDefaultPosition()
            "setSpeed" -> player.playbackParameters =
                PlaybackParameters((call.argument<Number>("speed") ?: 1.0).toFloat())
            "setVolume" -> player.volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
            "setQuality" -> setQuality(call.argument<Number>("height")?.toInt() ?: 0)
            // Renewed Live entitlement: only future licence requests use it.
            "renewToken" -> licence?.setKeyRequestProperty(
                "X-AxDRM-Message",
                call.argument<String>("token") ?: "",
            )
            "release" -> release()
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    /** 0 = automatic (ABR within the server cap), else a fixed height. */
    private fun setQuality(height: Int) {
        val builder = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
        if (height > 0) {
            for (group in player.currentTracks.groups) {
                if (group.type != C.TRACK_TYPE_VIDEO) continue
                for (i in 0 until group.length) {
                    if (group.getTrackFormat(i).height == height && group.isTrackSupported(i)) {
                        builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                        player.trackSelectionParameters = builder.build()
                        return
                    }
                }
            }
        }
        player.trackSelectionParameters = builder.build()
    }

    private fun videoHeights(tracks: Tracks): List<Int> =
        tracks.groups
            .filter { it.type == C.TRACK_TYPE_VIDEO }
            .flatMap { group -> (0 until group.length).filter { group.isTrackSupported(it) }.map { group.getTrackFormat(it).height } }
            .filter { it > 0 }
            .distinct()
            .sortedDescending()

    /** Same failure categories as the web player (protected-playback.ts). */
    private fun category(error: PlaybackException): String = when (error.errorCode) {
        PlaybackException.ERROR_CODE_DRM_SCHEME_UNSUPPORTED,
        PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
        PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES -> "capability"
        PlaybackException.ERROR_CODE_DRM_DISALLOWED_OPERATION -> "output"
        PlaybackException.ERROR_CODE_DRM_PROVISIONING_FAILED,
        PlaybackException.ERROR_CODE_DRM_SYSTEM_ERROR,
        PlaybackException.ERROR_CODE_DRM_DEVICE_REVOKED -> "drm_init"
        PlaybackException.ERROR_CODE_DRM_LICENSE_EXPIRED -> "expired"
        PlaybackException.ERROR_CODE_DRM_CONTENT_ERROR,
        PlaybackException.ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED,
        PlaybackException.ERROR_CODE_DRM_UNSPECIFIED -> "license"
        PlaybackException.ERROR_CODE_DECODING_FAILED,
        PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
        PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED -> "decode"
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> "timeout"
        PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> "behind_live"
        else -> "delivery"
    }

    /**
     * Whether DRM or the decoder failed: in D-070 mode B the Dart side then
     * continues on the clear copy (telemetry `fallback_reason` 2 or 3).
     */
    private fun kind(error: PlaybackException): String = when (error.errorCode) {
        in 6000..6999 -> "drm"
        in 4000..4999 -> "decoder"
        else -> "other"
    }

    /** HTTP status of a failed licence request, found in the cause chain. */
    private fun licenceHttpStatus(error: PlaybackException): Int? =
        generateSequence(error as Throwable) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()
            ?.takeIf { error.errorCode in 6000..6999 }
            ?.responseCode

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        emit(mapOf("event" to "tracks", "heights" to videoHeights(player.currentTracks)))
        main.post(ticker)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        main.removeCallbacks(ticker)
    }

    override fun getView(): View = surface

    override fun dispose() = release()

    private fun release() {
        if (released) return
        released = true
        main.removeCallbacks(ticker)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        player.release()
    }
}
