package com.mobin.mobin_vpn

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Quick Settings tile: shows the VPN state and toggles it through the app (same path as the home widget). */
@RequiresApi(Build.VERSION_CODES.N)
class MobinTileService : TileService() {
    companion object {
        const val PREFS = "mobin_native"
        const val KEY_CONNECTED = "connected"
    }

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val connected = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_CONNECTED, false)
        tile.state = if (connected) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Mobin VPN"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (connected) "متصل" else "قطع"
        }
        tile.updateTile()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val uri = Uri.parse("mobin://toggle")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(HomeWidgetLaunchIntent.getActivity(this, MainActivity::class.java, uri))
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
