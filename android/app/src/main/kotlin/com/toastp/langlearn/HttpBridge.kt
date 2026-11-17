package com.toastp.langlearn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class HttpBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.toastp.langlearn/http")
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("bad_url", "URL is empty", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val headers =
            call.argument<Map<String, String>>("headers") ?: emptyMap<String, String>()

        when (call.method) {
            "get" -> Thread { handleGet(url, headers, result) }.start()
            "download" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrBlank()) {
                    result.error("bad_path", "File path is empty", null)
                    return
                }
                Thread { handleDownload(url, headers, filePath, result) }.start()
            }
            else -> result.notImplemented()
        }
    }

    private fun handleGet(
        url: String,
        headers: Map<String, String>,
        result: MethodChannel.Result,
    ) {
        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(url, headers)
            val stream = if (connection.responseCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            val responseHeaders = HashMap<String, String>()
            for ((key, values) in connection.headerFields) {
                if (key != null && values.isNotEmpty()) {
                    responseHeaders[key] = values[0]
                }
            }
            val payload = mapOf(
                "status" to connection.responseCode,
                "body" to bytes,
                "url" to connection.url.toString(),
                "contentType" to (connection.contentType ?: ""),
                "headers" to responseHeaders,
            )
            mainHandler.post { result.success(payload) }
        } catch (error: Exception) {
            mainHandler.post {
                result.error("http_error", error.message ?: error.toString(), null)
            }
        } finally {
            connection?.disconnect()
        }
    }

    private fun handleDownload(
        url: String,
        headers: Map<String, String>,
        filePath: String,
        result: MethodChannel.Result,
    ) {
        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(url, headers)
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("HTTP " + connection.responseCode.toString())
            }
            val file = File(filePath)
            file.parentFile?.mkdirs()
            connection.inputStream.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output, 64 * 1024)
                }
            }
            mainHandler.post { result.success(filePath) }
        } catch (error: Exception) {
            mainHandler.post {
                result.error("download_error", error.message ?: error.toString(), null)
            }
        } finally {
            connection?.disconnect()
        }
    }

    private fun openConnection(
        url: String,
        headers: Map<String, String>,
    ): HttpURLConnection {
        var current = URL(url)
        var redirects = 0
        while (true) {
            val connection = current.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 20000
            connection.readTimeout = 30000
            connection.setRequestProperty("Accept-Encoding", "identity")
            for ((key, value) in headers) {
                connection.setRequestProperty(key, value)
            }
            val code = connection.responseCode
            if (code in 300..399) {
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank() || redirects >= 5) {
                    throw IllegalStateException("Too many redirects")
                }
                current = URL(current, location)
                redirects++
                continue
            }
            return connection
        }
    }
}
