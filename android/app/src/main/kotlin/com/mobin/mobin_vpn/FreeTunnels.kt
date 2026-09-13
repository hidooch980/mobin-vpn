package com.mobin.mobin_vpn

import android.content.Context
import ca.psiphon.PsiphonTunnel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Free routes that need no server list: Psiphon and Tor.
 *
 * Both run inside this app (Psiphon as a library, Tor as a child process) and expose a local SOCKS
 * port. Xray's VpnService then forwards all device traffic to that port. The app's own package is
 * excluded from the VPN, so their own network connections never loop back into the tunnel.
 */
object FreeTunnels {
    const val PSIPHON_SOCKS_PORT = 18190
    const val TOR_SOCKS_PORT = 19050

    // Public Psiphon Labs parameters for third-party clients (same values as other open clients).
    private const val REMOTE_SERVER_LIST_KEY =
        "MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM="

    // Public Tor Browser meek bridge (CDN fronted) used when Tor cannot connect directly.
    private const val MEEK_BRIDGE =
        "meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN"

    private val executor = Executors.newSingleThreadExecutor()
    private val log = ArrayDeque<String>()

    @Volatile var psiphonState = "idle" // idle | connecting | connected | failed
    @Volatile var torState = "idle"
    @Volatile var torProgress = 0

    private var psiphon: PsiphonTunnel? = null
    private var torProcess: Process? = null
    private var ptProcess: Process? = null

    @Synchronized
    private fun record(line: String) {
        log.addLast(line)
        while (log.size > 60) log.removeFirst()
    }

    @Synchronized
    fun drainLog(): List<String> = log.toList().also { log.clear() }

    // ---------------------------------------------------------------- Psiphon

    fun startPsiphon(context: Context) {
        stopPsiphon()
        psiphonState = "connecting"
        val app = context.applicationContext
        val config = JSONObject().apply {
            put("PropagationChannelId", "FFFFFFFFFFFFFFFF")
            put("SponsorId", "1111111111111111")
            put("ClientVersion", "1")
            put("DataDirectory", File(app.filesDir, "psiphon").apply { mkdirs() }.absolutePath)
            put("LocalSocksProxyPort", PSIPHON_SOCKS_PORT)
            put("EstablishTunnelTimeoutSeconds", 0)
            put("EmitBytesTransferred", true)
            put("RemoteServerListSignaturePublicKey", REMOTE_SERVER_LIST_KEY)
            put("ServerEntrySignaturePublicKey", "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=")
            put("ExchangeObfuscationKey", "DpXzloJk1Hw6aSzmKKky0xcahsEHubch81Mi6K0XMlU=")
        }.toString()

        val host = object : PsiphonTunnel.HostService {
            override fun getContext(): Context = app
            override fun getPsiphonConfig(): String = config
            override fun onConnecting() { psiphonState = "connecting"; record("psiphon: connecting") }
            override fun onConnected() { psiphonState = "connected"; record("psiphon: connected") }
            override fun onListeningSocksProxyPort(port: Int) = record("psiphon: socks on $port")
            override fun onExiting() {
                if (psiphonState != "idle") psiphonState = "failed"
                record("psiphon: exiting")
            }
            override fun onDiagnosticMessage(message: String) {
                if (message.contains("error", ignoreCase = true)) record("psiphon: $message")
            }
        }
        executor.execute {
            try {
                val tunnel = PsiphonTunnel.newPsiphonTunnel(host)
                tunnel.setVpnMode(false)
                psiphon = tunnel
                val entries = runCatching { app.assets.open("server_entries.txt").bufferedReader().readText().trim() }
                    .getOrDefault("")
                tunnel.startTunneling(entries)
            } catch (e: Exception) {
                psiphonState = "failed"
                record("psiphon: start failed: ${e.message}")
            }
        }
    }

    fun stopPsiphon() {
        val tunnel = psiphon ?: return
        psiphon = null
        psiphonState = "idle"
        executor.execute { runCatching { tunnel.stop() } }
    }

    // ---------------------------------------------------------------- Tor

    fun startTor(context: Context) {
        stopTor()
        torState = "connecting"
        torProgress = 0
        val app = context.applicationContext
        Thread {
            // Direct first; if Tor is blocked, fall back to a CDN-fronted meek bridge.
            if (!runTor(app, bridge = false, budgetMs = 45_000) && torState == "connecting") {
                record("tor: direct did not bootstrap, trying meek bridge")
                if (!runTor(app, bridge = true, budgetMs = 150_000) && torState == "connecting") {
                    torState = "failed"
                }
            }
        }.start()
    }

    private fun nativeFile(context: Context, name: String) = File(context.applicationInfo.nativeLibraryDir, name)

    private fun runTor(context: Context, bridge: Boolean, budgetMs: Long): Boolean {
        val tor = nativeFile(context, "libtor.so")
        if (!tor.exists()) {
            record("tor: binary missing in this build")
            torState = "failed"
            return false
        }
        val dataDir = File(context.filesDir, "tor").apply { mkdirs() }
        var ptListener: String? = null
        if (bridge) {
            ptListener = startMeek(context, dataDir) ?: return false
        }
        val torrc = File(dataDir, "torrc")
        torrc.writeText(buildString {
            appendLine("SocksPort 127.0.0.1:$TOR_SOCKS_PORT")
            appendLine("DataDirectory ${File(dataDir, "data").apply { mkdirs() }.absolutePath}")
            appendLine("ClientOnly 1")
            appendLine("SocksPolicy accept 127.0.0.0/8")
            appendLine("SocksPolicy reject *")
            appendLine("Log notice stdout")
            appendLine("AvoidDiskWrites 1")
            appendLine("NumEntryGuards 1")
            appendLine("CircuitBuildTimeout ${if (bridge) 120 else 60}")
            appendLine("KeepalivePeriod 30")
            if (ptListener != null) {
                appendLine("UseBridges 1")
                appendLine("ClientTransportPlugin meek_lite socks5 $ptListener")
                appendLine("Bridge $MEEK_BRIDGE")
            }
        })
        val process = ProcessBuilder(tor.absolutePath, "-f", torrc.absolutePath)
            .directory(dataDir)
            .redirectErrorStream(true)
            .start()
        torProcess = process
        val deadline = System.currentTimeMillis() + budgetMs
        val done = Regex("Bootstrapped (\\d+)%")
        val reader = Thread {
            runCatching {
                process.inputStream.bufferedReader().forEachLine { line ->
                    done.find(line)?.groupValues?.get(1)?.toIntOrNull()?.let { torProgress = it }
                    if (line.contains("[warn]") || line.contains("[err]") || line.contains("Bootstrapped")) record("tor: $line")
                    if (torProgress >= 100) torState = "connected"
                }
            }
        }.apply { start() }
        while (System.currentTimeMillis() < deadline && torState == "connecting") {
            if (!process.isAlive) break
            Thread.sleep(300)
        }
        if (torState == "connected") return true
        process.destroy()
        reader.interrupt()
        ptProcess?.destroy()
        ptProcess = null
        if (torProcess === process) torProcess = null
        return false
    }

    /** Starts lyrebird (obfs4proxy) as a managed pluggable transport and returns its SOCKS listener. */
    private fun startMeek(context: Context, dataDir: File): String? {
        val binary = nativeFile(context, "libobfs4proxy.so")
        if (!binary.exists()) {
            record("tor: pluggable transport missing in this build")
            return null
        }
        val builder = ProcessBuilder(binary.absolutePath).directory(dataDir).redirectErrorStream(true)
        builder.environment().apply {
            put("TOR_PT_MANAGED_TRANSPORT_VER", "1")
            put("TOR_PT_STATE_LOCATION", File(dataDir, "pt").apply { mkdirs() }.absolutePath)
            put("TOR_PT_CLIENT_TRANSPORTS", "meek_lite")
            put("TOR_PT_EXIT_ON_STDIN_CLOSE", "0")
        }
        val process = builder.start()
        ptProcess = process
        val method = Regex("CMETHOD meek_lite socks5 (\\S+)")
        val reader = process.inputStream.bufferedReader()
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            val line = reader.readLine() ?: break
            method.find(line)?.let { match ->
                Thread { runCatching { reader.forEachLine { } } }.start()
                return match.groupValues[1]
            }
        }
        record("tor: pluggable transport did not start")
        process.destroy()
        return null
    }

    fun stopTor() {
        torState = "idle"
        torProgress = 0
        torProcess?.destroy()
        torProcess = null
        ptProcess?.destroy()
        ptProcess = null
    }

    fun status(): Map<String, Any> = mapOf(
        "psiphon" to psiphonState,
        "tor" to torState,
        "torProgress" to torProgress,
        "log" to drainLog(),
    )
}
