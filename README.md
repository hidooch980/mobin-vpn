# Mobin VPN

One-button VPN client for **Android** and **Windows**, fed by the tested server list from
[hidooch980/vpn-sub](https://github.com/hidooch980/vpn-sub).

- **Smart mode:** measures real delay to many servers *from the user's own internet*, connects to the fastest one and retries the next if it fails.
- **Locations:** pick a country; the fastest server there is used.
- **Gaming:** servers near Iran, re-tested for average ping + jitter.
- **Advanced:** settings (reconnect, proxy-only, Iran bypass, DNS, pool size, test URL, protocols, custom subscription), full server list with ping test.
- **Pro:** split tunneling (Android), full-device TUN VPN as administrator (Windows), kill switch, TLS fragment anti-censorship, daily/monthly usage stats.
- **Extras:** home-screen widget and Quick Settings tile (Android), favorites, "My configs" import by paste or QR, Cloudflare WARP chained behind the server, start with Windows.
- **Protocols:** VLESS, VMess, Trojan, Shadowsocks (both); Hysteria2, TUIC, AnyTLS, WireGuard, SOCKS, HTTP (Windows).
- **Updates:** on launch the app checks the latest GitHub Release; one tap downloads it (Android opens the installer, Windows swaps files and relaunches). The server list refreshes on every launch.

Download from **[Releases](../../releases/latest)**.

## How it works
| | Android | Windows |
|---|---|---|
| Core | Xray via `flutter_v2ray` (VpnService, whole device) | bundled `sing-box.exe` (local proxy + Windows system proxy) |
| Protocols | VLESS, VMess, Trojan, Shadowsocks | + Hysteria2, TUIC |
| Delay test | Xray real delay per server | sing-box Clash API `/proxies/:name/delay` |

The server list is fetched from GitHub raw with jsDelivr mirrors and cached for offline start.

## Code map
- `lib/core/server.dart`: subscription parsing and names (country/number from `Mobin ✦ 🇩🇪 Germany 03 · VLESS`)
- `lib/core/singbox_outbound.dart`: share link → sing-box outbound (port of `vpn-aggregator/parsers.py`)
- `lib/core/vpn_controller.dart`: smart selection, ping, connect with failover
- `lib/core/android_engine.dart`, `lib/core/windows_engine.dart`: platform cores
- `lib/ui/`: animated aurora background, connect orb, location and share sheets

## Build & release
Every push to `main` runs `.github/workflows/release.yml`: analyze + tests, APKs (universal, arm64, armv7),
Windows zip with sing-box, then publishes GitHub Release `v1.0.<run>`.

APK signing uses repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (falls back to a debug key without them — then each release
must be uninstalled before installing the next).

Local: `flutter pub get && flutter test && flutter run -d windows` (copy `sing-box.exe` next to the built exe).
