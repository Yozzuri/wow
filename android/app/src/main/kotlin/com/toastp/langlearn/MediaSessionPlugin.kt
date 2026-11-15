package com.toastp.langlearn

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaSessionPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val listenerComponent =
        ComponentName(context, MediaNotificationListenerService::class.java)
    private val manager =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager

    private var eventSink: EventChannel.EventSink? = null
    private var boundController: MediaController? = null
    private var listenerAttached = false

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = emitNow()

        override fun onPlaybackStateChanged(state: PlaybackState?) = emitNow()

        override fun onSessionDestroyed() {
            bindController(null)
        }
    }

    private val sessionsChangedListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            val next = pickController(controllers ?: emptyList())
            bindController(next)
        }

    init {
        channel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAccess" -> result.success(hasNotificationAccess())
            "openSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                result.success(null)
            }
            "getNowPlaying" -> result.success(getNowPlaying())
            "seekTo" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                try {
                    resolveActiveController()?.transportControls?.seekTo(positionMs)
                    result.success(null)
                } catch (_: Exception) {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (!hasNotificationAccess()) {
            events?.success(null)
            return
        }
        attachListener()
        bindController(resolveActiveController())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        detachListener()
        bindController(null)
    }

    private fun attachListener() {
        if (listenerAttached) {
            return
        }
        try {
            manager.addOnActiveSessionsChangedListener(
                sessionsChangedListener,
                listenerComponent,
            )
            listenerAttached = true
        } catch (_: Exception) {
        }
    }

    private fun detachListener() {
        if (!listenerAttached) {
            return
        }
        try {
            manager.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (_: Exception) {
        }
        listenerAttached = false
    }

    private fun bindController(controller: MediaController?) {
        if (boundController === controller) {
            emitNow()
            return
        }
        try {
            boundController?.unregisterCallback(controllerCallback)
        } catch (_: Exception) {
        }
        boundController = controller
        try {
            controller?.registerCallback(controllerCallback)
        } catch (_: Exception) {
        }
        emitNow()
    }

    private fun emitNow() {
        val sink = eventSink ?: return
        val controller = boundController ?: resolveActiveController()
        if (controller == null) {
            sink.success(null)
            return
        }
        try {
            sink.success(buildNowPlaying(controller))
        } catch (_: Exception) {
            sink.success(null)
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any { flat ->
            val component = ComponentName.unflattenFromString(flat)
            component?.packageName == context.packageName
        }
    }

    private fun getNowPlaying(): Map<String, Any?>? {
        if (!hasNotificationAccess()) {
            return null
        }
        return try {
            val controller = resolveActiveController() ?: return null
            buildNowPlaying(controller)
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveActiveController(): MediaController? {
        return try {
            pickController(manager.getActiveSessions(listenerComponent))
        } catch (_: Exception) {
            null
        }
    }

    private fun pickController(controllers: List<MediaController>): MediaController? {
        return controllers.firstOrNull { controller ->
            isPlaying(controller) && controller.title() != null
        } ?: controllers.firstOrNull { it.title() != null }
    }

    private fun isPlaying(controller: MediaController): Boolean {
        val state = controller.playbackState?.state
        return state == PlaybackState.STATE_PLAYING ||
            state == PlaybackState.STATE_BUFFERING
    }

    private fun MediaController.title(): String? =
        metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() }

    private fun buildNowPlaying(controller: MediaController): Map<String, Any?> {
        val metadata = controller.metadata
        val playback = controller.playbackState
        var position = playback?.position ?: 0L
        if (playback?.state == PlaybackState.STATE_PLAYING) {
            val elapsed = SystemClock.elapsedRealtime() - playback.lastPositionUpdateTime
            position += (elapsed * playback.playbackSpeed).toLong()
        }
        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        if (duration > 0 && position > duration) {
            position = duration
        }
        return mapOf(
            "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
            "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "packageName" to controller.packageName,
            "durationMs" to duration,
            "positionMs" to position,
            "isPlaying" to (playback?.state == PlaybackState.STATE_PLAYING),
        )
    }

    companion object {
        private const val CHANNEL = "langlearn/media_session"
        private const val EVENT_CHANNEL = "langlearn/media_session/events"
    }
}
