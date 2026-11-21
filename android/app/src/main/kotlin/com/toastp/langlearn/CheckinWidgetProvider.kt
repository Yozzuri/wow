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
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context, streak, checked),
            )
        }
    }

    companion object {
        private const val PREFS = "langlearn_widget"
        private const val KEY_DATES = "checkin_dates"
        private const val KEY_STREAK = "checkin_streak"
        private const val KEY_ACHIEVEMENTS = "checkin_achievements"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun saveState(
            context: Context,
            dates: List<String>,
            streak: Int,
            achievements: String,
        ) {
            prefs(context)
                .edit()
                .putString(KEY_DATES, dates.joinToString(","))
                .putInt(KEY_STREAK, streak)
                .putString(KEY_ACHIEVEMENTS, achievements)
                .apply()
        }

        fun loadDates(context: Context): Set<String> {
            val raw = prefs(context).getString(KEY_DATES, "") ?: ""
            if (raw.isEmpty()) {
                return emptySet()
            }
            return raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
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
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context, streak, checked))
            }
        }

        private fun buildViews(
            context: Context,
            streak: Int,
            checkedToday: Boolean,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.checkin_widget)
            views.setTextViewText(R.id.widget_streak, streak.toString())
            views.setTextViewText(
                R.id.widget_status,
                if (checkedToday) "今日已打卡" else "今日待打卡",
            )
            views.setTextViewText(
                R.id.widget_achievements,
                prefs(context).getString(KEY_ACHIEVEMENTS, "") ?: "",
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
