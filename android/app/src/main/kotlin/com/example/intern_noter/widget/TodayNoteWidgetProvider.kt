package com.example.intern_noter.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.example.intern_noter.MainActivity
import com.example.intern_noter.R
import java.util.Calendar
import java.util.Locale

class TodayNoteWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "com.example.intern_noter.widget.ACTION_REFRESH"
        const val ACTION_OPEN_QUICK_NOTE = "com.example.intern_noter.widget.ACTION_OPEN_QUICK_NOTE"
        const val EXTRA_OPEN_TODAY = "open_today"

        private const val REQUEST_OPEN_TODAY = 1001
        private const val REQUEST_QUICK_NOTE = 1002
        private const val MAX_VISIBLE_LINES = 5

        private val LINE_VIEW_IDS = intArrayOf(
            R.id.tv_widget_line_1,
            R.id.tv_widget_line_2,
            R.id.tv_widget_line_3,
            R.id.tv_widget_line_4,
            R.id.tv_widget_line_5,
        )

        private val MULTILINE_WHITESPACE_REGEX = Regex("\\s*\\n+\\s*")

        @JvmStatic
        fun updateAllWidgets(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val componentName = ComponentName(appContext, TodayNoteWidgetProvider::class.java)
            val appWidgetIds = manager.getAppWidgetIds(componentName)
            if (appWidgetIds.isEmpty()) {
                return
            }
            val now = Calendar.getInstance()
            val summary = WidgetDbHelper(appContext).use {
                it.getTodaySummary(IndonesianDates.todayIso(now))
            }
            val views = buildRemoteViews(appContext, summary, now)
            for (appWidgetId in appWidgetIds) {
                manager.updateAppWidget(appWidgetId, views)
            }
        }

        private fun buildRemoteViews(
            context: Context,
            summary: TodaySummary,
            now: Calendar,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_today_note)

            views.setTextViewText(R.id.tv_widget_date, IndonesianDates.formatShortDate(now))

            val hasHours = summary.totalHours > 0.0
            val hoursText = String.format(Locale.US, "%.1f j", summary.totalHours)
            views.setTextViewText(R.id.tv_widget_hours, hoursText)
            views.setInt(
                R.id.tv_widget_hours,
                "setBackgroundResource",
                if (hasHours) R.drawable.widget_badge_bg else R.drawable.chip_bg,
            )
            val badgeTextColorRes =
                if (hasHours) R.color.widget_accent else R.color.widget_ink_muted
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColor(R.id.tv_widget_hours, "setTextColor", badgeTextColorRes)
            } else {
                views.setTextColor(R.id.tv_widget_hours, context.getColor(badgeTextColorRes))
            }

            if (summary.lines.isEmpty()) {
                views.setViewVisibility(R.id.tv_widget_empty, View.VISIBLE)
                for (viewId in LINE_VIEW_IDS) {
                    views.setViewVisibility(viewId, View.GONE)
                }
                views.setViewVisibility(R.id.tv_widget_more, View.GONE)
            } else {
                views.setViewVisibility(R.id.tv_widget_empty, View.GONE)
                for (i in 0 until MAX_VISIBLE_LINES) {
                    val viewId = LINE_VIEW_IDS[i]
                    if (i < summary.lines.size) {
                        val line = summary.lines[i]
                        val modul = line.modul.trim()
                        val prefix = if (modul.isNotEmpty()) "[$modul] " else ""
                        val cleanDescription = line.description
                            .replace(MULTILINE_WHITESPACE_REGEX, " ")
                            .trim()
                        views.setTextViewText(viewId, "\u2022 $prefix$cleanDescription")
                        views.setViewVisibility(viewId, View.VISIBLE)
                    } else {
                        views.setViewVisibility(viewId, View.GONE)
                    }
                }

                val remaining = summary.lines.size - MAX_VISIBLE_LINES
                if (remaining > 0) {
                    views.setTextViewText(
                        R.id.tv_widget_more,
                        "+$remaining catatan lainnya...",
                    )
                    views.setViewVisibility(R.id.tv_widget_more, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.tv_widget_more, View.GONE)
                }
            }

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val openMainIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra(EXTRA_OPEN_TODAY, true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openMainPendingIntent = PendingIntent.getActivity(
                context,
                REQUEST_OPEN_TODAY,
                openMainIntent,
                pendingFlags,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openMainPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_header, openMainPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_body, openMainPendingIntent)

            val quickNoteIntent = Intent(context, QuickNoteActivity::class.java).apply {
                action = ACTION_OPEN_QUICK_NOTE
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val quickNotePendingIntent = PendingIntent.getActivity(
                context,
                REQUEST_QUICK_NOTE,
                quickNoteIntent,
                pendingFlags,
            )
            views.setOnClickPendingIntent(R.id.widget_input_bar, quickNotePendingIntent)

            return views
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            ACTION_REFRESH,
            -> updateAllWidgets(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        if (appWidgetIds.isEmpty()) return
        val appContext = context.applicationContext
        val now = Calendar.getInstance()
        val summary = WidgetDbHelper(appContext).use {
            it.getTodaySummary(IndonesianDates.todayIso(now))
        }
        val views = buildRemoteViews(appContext, summary, now)
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
