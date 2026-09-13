package com.mobin.mobin_vpn

import android.content.ComponentName
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.TelephonyManager
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
                // Executables must live in the extracted native library dir (bundled sing-box: libsingbox.so).
                "nativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                // Connection type of the underlying (non-VPN) network and the SIM operator name.
                "networkInfo" -> {
                    val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    var type = "none"
                    for (network in cm.allNetworks) {
                        val caps = cm.getNetworkCapabilities(network) ?: continue
                        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                        type = when {
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                            else -> type
                        }
                        if (type == "wifi") break
                    }
                    val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
                    result.success(mapOf("type" to type, "operator" to tm.networkOperatorName))
                }
                else -> result.notImplemented()
            }
        }
    }
}
