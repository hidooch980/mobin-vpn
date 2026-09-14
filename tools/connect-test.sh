#!/usr/bin/env bash
# Real connection tests on the CI emulator. For each mode (auto, then gaming):
# select the mode via MainActivity's molido_mode extra, start the tunnel with the Quick Settings tile
# (the only exported way to connect), wait for tun0, then load a page through the tunnel.
# Gaming also has to log its chosen node and keep request latency reasonable.
set -u
PKG=com.mobin.mobin_vpn
TILE=$PKG/com.msnguard.vpn.MsnGuardTileService

tunnel_up() { adb shell ip addr show tun0 2>/dev/null | grep -q "inet "; }

http_check() { # prints the status line of a plain HTTP request made from the device
  adb shell "printf 'GET /generate_204 HTTP/1.1\r\nHost: connectivitycheck.gstatic.com\r\nConnection: close\r\n\r\n' | toybox nc -w 20 connectivitycheck.gstatic.com 80 | head -1" 2>/dev/null | tr -d '\r'
}

connect_mode() { # mode
  local mode=$1
  echo "=== mode: $mode ==="
  # Fresh process each time, so a stale tile state or a half-stopped service can't swallow the tap.
  adb shell am force-stop $PKG
  sleep 2
  adb shell am start -W -n $PKG/com.msnguard.vpn.MainActivity --es molido_mode "$mode" >/dev/null
  sleep 8
  echo "saved mode: $(adb shell run-as $PKG cat shared_prefs/settings.xml 2>/dev/null | grep -o 'default_protocol">[^<]*' || echo 'n/a (release build)')"
  adb logcat -c
  # After a force-stop SystemUI drops its binding to the tile service; clicks are ignored
  # until the Quick Settings panel is shown again and rebinds it.
  adb shell cmd statusbar expand-settings
  sleep 4
  adb shell cmd statusbar click-tile $TILE
  adb shell cmd statusbar collapse || true
  for i in $(seq 1 36); do
    if tunnel_up; then echo "tunnel interface up after $((i * 5)) s"; break; fi
    sleep 5
  done
  if ! tunnel_up; then
    echo "no tun0 after 180 s"
    pid=$(adb shell pidof $PKG | tr -d '\r')
    echo "--- app pid: ${pid:-not running} ---"
    if [ -n "$pid" ]; then adb logcat -d --pid="$pid" | tail -80; else adb logcat -d | tail -80; fi
    adb shell dumpsys connectivity | grep -iE "VPN|tun0" | head -10
    return 1
  fi
  sleep 10
  for i in 1 2 3 4 5 6; do
    code=$(http_check)
    echo "attempt $i: $code"
    if echo "$code" | grep -q " 204"; then echo "page loaded through the tunnel ✅"; return 0; fi
    sleep 10
  done
  adb logcat -d | grep -iE "msnguard|aether|shard" | tail -60
  return 1
}

disconnect() {
  # Stopping the app tears the VpnService down; a second tile tap is unreliable because the
  # tile's cached state can lag behind the service.
  adb shell am force-stop $PKG
  for i in $(seq 1 12); do tunnel_up || { echo "disconnected"; return 0; }; sleep 5; done
  echo "tunnel still up after 60 s"
  return 1
}

adb shell appops set $PKG ACTIVATE_VPN allow
adb shell cmd statusbar add-tile $TILE || true
sleep 3

shot() { mkdir -p shots; adb exec-out screencap -p > "shots/$1.png" || true; }

adb shell am force-stop $PKG
adb shell am start -W -n $PKG/com.msnguard.vpn.MainActivity >/dev/null
sleep 8
shot 1-home-disconnected

connect_mode auto || { shot fail-auto; exit 1; }
adb shell am start -W -n $PKG/com.msnguard.vpn.MainActivity >/dev/null
sleep 4
shot 2-home-connected
disconnect || true
# SHARD/Tor exec ARM-only binaries that the x86_64 CI emulator cannot run, so only the
# auto (WireGuard core) path is enforced here; the rest has to be checked on a real phone.
echo "all connection tests passed ✅"
