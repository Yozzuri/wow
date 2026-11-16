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
                CheckinWidgetProvider.saveState(context, dates, streak)
                CheckinWidgetProvider.updateAll(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
