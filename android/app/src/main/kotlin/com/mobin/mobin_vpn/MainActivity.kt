package com.mobin.mobin_vpn

import android.content.ComponentName
import android.os.Build
import android.service.quicksettings.TileService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobin/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "setVpnState" -> {
                    val connected = call.argument<Boolean>("connected") ?: false
                    getSharedPreferences(MobinTileService.PREFS, MODE_PRIVATE).edit()
                        .putBoolean(MobinTileService.KEY_CONNECTED, connected)
                        .apply()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        TileService.requestListeningState(this, ComponentName(this, MobinTileService::class.java))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
