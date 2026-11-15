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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaSessionPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val listenerComponent =
        ComponentName(context, MediaNotificationListenerService::class.java)
    private val manager =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager

    init {
        channel.setMethodCallHandler(this)
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
                    activeController()?.transportControls?.seekTo(positionMs)
                    result.success(null)
                } catch (_: Exception) {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
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
            val controller = activeController() ?: return null
            buildNowPlaying(controller)
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun activeController(): MediaController? {
        val controllers = manager.getActiveSessions(listenerComponent)
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
    }
}
