package de.fenron.lifeos

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class LifeOsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.lifeos_widget).apply {
                val expiryCount = widgetData.getInt("expiry_count", 0)
                val expirySummary = widgetData.getString("expiry_summary", "") ?: ""
                val taskCount = widgetData.getInt("task_count", 0)
                val taskSummary = widgetData.getString("task_summary", "") ?: ""

                val expiryHeader = if (expiryCount > 0)
                    "⚠ $expiryCount ablaufend"
                else
                    "✓ Nichts läuft ab"

                val taskHeader = if (taskCount > 0)
                    "☑ $taskCount Aufgabe${if (taskCount == 1) "" else "n"} offen"
                else
                    "✓ Alle erledigt"

                setTextViewText(R.id.widget_expiry_header, expiryHeader)
                setTextViewText(R.id.widget_expiry_items, expirySummary)
                setTextViewText(R.id.widget_task_header, taskHeader)
                setTextViewText(R.id.widget_task_items, taskSummary)

                // Tap opens the app
                val launchIntent = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_root, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
