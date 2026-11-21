package com.toastp.langlearn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class CheckinWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val dates = loadDates(context)
        val today = dayKey(Calendar.getInstance().time)
        val streak = computeStreak(dates, Calendar.getInstance())
        val checked = dates.contains(today)
        val scores = loadScores(context)
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, streak, checked, scores),
            )
        }
    }

    companion object {
        private const val PREFS = "langlearn_widget"
        private const val KEY_DATES = "checkin_dates"
        private const val KEY_STREAK = "checkin_streak"
        private const val KEY_REGULAR = "challenge_regular"
        private const val KEY_CONFIDENTIAL = "challenge_confidential"
        private const val KEY_TOP_SECRET = "challenge_top_secret"

        data class Scores(
            val regular: Double,
            val confidential: Double,
            val topSecret: Double,
        )

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun saveState(
            context: Context,
            dates: List<String>,
            streak: Int,
            regular: Double,
            confidential: Double,
            topSecret: Double,
        ) {
            prefs(context)
                .edit()
                .putString(KEY_DATES, dates.joinToString(","))
                .putInt(KEY_STREAK, streak)
                .putFloat(KEY_REGULAR, regular.toFloat())
                .putFloat(KEY_CONFIDENTIAL, confidential.toFloat())
                .putFloat(KEY_TOP_SECRET, topSecret.toFloat())
                .apply()
        }

        fun loadDates(context: Context): Set<String> {
            val raw = prefs(context).getString(KEY_DATES, "") ?: ""
            if (raw.isEmpty()) {
                return emptySet()
            }
            return raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        }

        private fun loadScores(context: Context): Scores {
            val p = prefs(context)
            return Scores(
                p.getFloat(KEY_REGULAR, -1f).toDouble(),
                p.getFloat(KEY_CONFIDENTIAL, -1f).toDouble(),
                p.getFloat(KEY_TOP_SECRET, -1f).toDouble(),
            )
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CheckinWidgetProvider::class.java),
            )
            if (ids.isEmpty()) {
                return
            }
            val dates = loadDates(context)
            val today = dayKey(Calendar.getInstance().time)
            val streak = computeStreak(dates, Calendar.getInstance())
            val checked = dates.contains(today)
            val scores = loadScores(context)
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context, streak, checked, scores))
            }
        }

        private fun buildViews(
            context: Context,
            streak: Int,
            checkedToday: Boolean,
            scores: Scores,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.checkin_widget)
            views.setTextViewText(R.id.widget_streak, streak.toString())
            views.setTextViewText(
                R.id.widget_status,
                if (checkedToday) "今日已打卡" else "今日待打卡",
            )
            val parts = mutableListOf<String>()
            fun add(label: String, value: Double) {
                parts.add(
                    if (value >= 0) {
                        String.format(Locale.US, "%s %.1f", label, value)
                    } else {
                        label + " --"
                    },
                )
            }
            add("常规", scores.regular)
            add("机密", scores.confidential)
            add("绝密", scores.topSecret)
            views.setTextViewText(
                R.id.widget_scores,
                parts.joinToString("   "),
            )
            val intent = Intent(context, MainActivity::class.java)
            val pending = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            return views
        }

        private fun dayKey(date: Date): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)

        private fun computeStreak(dates: Set<String>, calendar: Calendar): Int {
            val cursor = Calendar.getInstance().apply {
                time = calendar.time
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (!dates.contains(dayKey(cursor.time))) {
                cursor.add(Calendar.DAY_OF_YEAR, -1)
            }
            var streak = 0
            while (dates.contains(dayKey(cursor.time))) {
                streak++
                cursor.add(Calendar.DAY_OF_YEAR, -1)
            }
            return streak
        }
    }
}
