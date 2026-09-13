package com.mobin.mobin_vpn

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget: status, location and a connect button. Data comes from Dart via home_widget. */
class MobinWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val connected = widgetData.getBoolean("connected", false)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.mobin_widget).apply {
                setTextViewText(R.id.widget_status, widgetData.getString("status", "آماده‌ی اتصال"))
                setTextViewText(R.id.widget_location, widgetData.getString("location", "هوشمند"))
                setTextViewText(R.id.widget_button, if (connected) "قطع اتصال" else "اتصال")
                setInt(
                    R.id.widget_button,
                    "setBackgroundResource",
                    if (connected) R.drawable.widget_button_on else R.drawable.widget_button_off,
                )
                setImageViewResource(R.id.widget_icon, if (connected) R.drawable.ic_tile_shield_on else R.drawable.ic_tile_shield)
                setOnClickPendingIntent(
                    R.id.widget_button,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("mobin://toggle")),
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("mobin://open")),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
