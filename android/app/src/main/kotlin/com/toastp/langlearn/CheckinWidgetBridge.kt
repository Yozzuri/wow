package com.toastp.langlearn

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CheckinWidgetBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.toastp.langlearn/widget")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateCheckin" -> {
                val dates = call.argument<List<String>>("dates") ?: emptyList()
                val streak = call.argument<Int>("streak") ?: 0
                val achievements = call.argument<String>("achievements") ?: ""
                CheckinWidgetProvider.saveState(
                    context,
                    dates,
                    streak,
                    achievements,
                )
                CheckinWidgetProvider.updateAll(context)
                result.success(null)
            }
            "updateChallenge" -> {
                val averages = call.argument<String>("averages") ?: "--|--|--"
                val rank = call.argument<String>("rank") ?: ""
                val season = call.argument<String>("season") ?: ""
                val achievements = call.argument<String>("achievements") ?: ""
                ChallengeWidgetProvider.saveState(
                    context,
                    averages,
                    rank,
                    season,
                    achievements,
                )
                ChallengeWidgetProvider.updateAll(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
