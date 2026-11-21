package com.toastp.langlearn

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class ChallengeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildViews(context),
            )
        }
    }

    companion object {
        private const val PREFS = "langlearn_widget"
        private const val KEY_AVERAGES = "challenge_averages"
        private const val KEY_RANK = "challenge_rank"
        private const val KEY_SEASON = "challenge_season"
        private const val KEY_ACHIEVEMENTS = "challenge_achievements"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun saveState(
            context: Context,
            averages: String,
            rank: String,
            season: String,
            achievements: String,
        ) {
            prefs(context)
                .edit()
                .putString(KEY_AVERAGES, averages)
                .putString(KEY_RANK, rank)
                .putString(KEY_SEASON, season)
                .putString(KEY_ACHIEVEMENTS, achievements)
                .apply()
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ChallengeWidgetProvider::class.java),
            )
            if (ids.isEmpty()) {
                return
            }
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val p = prefs(context)
            val views = RemoteViews(context.packageName, R.layout.challenge_widget)
            views.setTextViewText(
                R.id.challenge_averages,
                p.getString(KEY_AVERAGES, "--|--|--") ?: "--|--|--",
            )
            views.setTextViewText(
                R.id.challenge_rank,
                p.getString(KEY_RANK, "青铜 III ☆☆☆☆") ?: "青铜 III ☆☆☆☆",
            )
            views.setTextViewText(
                R.id.challenge_season,
                p.getString(KEY_SEASON, "") ?: "",
            )
            views.setTextViewText(
                R.id.challenge_achievements,
                p.getString(KEY_ACHIEVEMENTS, "") ?: "",
            )
            val intent = Intent(context, MainActivity::class.java)
            val pending = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.challenge_widget_root, pending)
            return views
        }
    }
}
