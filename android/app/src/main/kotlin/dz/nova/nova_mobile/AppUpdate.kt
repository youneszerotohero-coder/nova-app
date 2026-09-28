package dz.nova.nova_mobile

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Google Play in-app updates (owner request 2026-09-26) on `nova/app_update`:
 *
 *  - `info`     what Play offers this install; nothing for an install that
 *               did not come from Play (debug, sideloaded APK)
 *  - `start`    `{immediate}`: Play's own flow, answering `ok`, `canceled`
 *               or `failed`
 *  - `complete` installs a downloaded flexible update (the app restarts)
 *
 * Flexible download progress leaves on `nova/app_update/events`.
 */
object AppUpdate {
    fun register(engine: FlutterEngine, activity: Activity) {
        val messenger = engine.dartExecutor.binaryMessenger
        val manager: AppUpdateManager = AppUpdateManagerFactory.create(activity)
        var latest: AppUpdateInfo? = null
        var sink: EventChannel.EventSink? = null
        val listener = InstallStateUpdatedListener { state ->
            sink?.success(
                mapOf(
                    "status" to status(state.installStatus()),
                    "downloaded" to state.bytesDownloaded(),
                    "total" to state.totalBytesToDownload(),
                ),
            )
        }

        EventChannel(messenger, "nova/app_update/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    manager.registerListener(listener)
                }

                override fun onCancel(arguments: Any?) {
                    manager.unregisterListener(listener)
                    sink = null
                }
            },
        )

        MethodChannel(messenger, "nova/app_update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> manager.appUpdateInfo
                    .addOnSuccessListener { info ->
                        latest = info
                        result.success(describe(info))
                    }
                    .addOnFailureListener { result.success(mapOf("available" to false)) }
                "start" -> {
                    val info = latest
                    val type = if (call.argument<Boolean>("immediate") == true) {
                        AppUpdateType.IMMEDIATE
                    } else {
                        AppUpdateType.FLEXIBLE
                    }
                    if (info == null || !info.isUpdateTypeAllowed(type)) {
                        result.success("failed")
                    } else {
                        // An AppUpdateInfo starts one flow only.
                        latest = null
                        manager.startUpdateFlow(info, activity, AppUpdateOptions.newBuilder(type).build())
                            .addOnSuccessListener { code ->
                                result.success(
                                    when (code) {
                                        Activity.RESULT_OK -> "ok"
                                        Activity.RESULT_CANCELED -> "canceled"
                                        else -> "failed"
                                    },
                                )
                            }
                            .addOnFailureListener { result.success("failed") }
                    }
                }
                "complete" -> {
                    manager.completeUpdate()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun describe(info: AppUpdateInfo): Map<String, Any?> = mapOf(
        "available" to (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
        "inProgress" to (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS),
        "downloaded" to (info.installStatus() == InstallStatus.DOWNLOADED),
        "versionCode" to info.availableVersionCode(),
        "priority" to info.updatePriority(),
        "stalenessDays" to info.clientVersionStalenessDays(),
        "flexible" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        "immediate" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
    )

    private fun status(value: Int): String = when (value) {
        InstallStatus.PENDING -> "pending"
        InstallStatus.DOWNLOADING -> "downloading"
        InstallStatus.DOWNLOADED -> "downloaded"
        InstallStatus.INSTALLING -> "installing"
        InstallStatus.INSTALLED -> "installed"
        InstallStatus.FAILED -> "failed"
        InstallStatus.CANCELED -> "canceled"
        else -> "unknown"
    }
}
