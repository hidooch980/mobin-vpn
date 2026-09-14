#!/usr/bin/env bash
# Real connection test on the CI emulator: grants VPN consent, taps the Quick Settings tile
# (the only exported way to start the tunnel), then checks for a VPN network and a page load through it.
set -u
PKG=com.mobin.mobin_vpn
TILE=$PKG/com.msnguard.vpn.MsnGuardTileService

adb shell appops set $PKG ACTIVATE_VPN allow
adb shell cmd statusbar add-tile $TILE || true
sleep 3
adb shell cmd statusbar click-tile $TILE
adb shell cmd statusbar collapse || true

for i in $(seq 1 36); do
  if adb shell ip addr show tun0 2>/dev/null | grep -q "inet "; then
    echo "tunnel interface up after $((i * 5)) s"
    break
  fi
  sleep 5
done
if ! adb shell ip addr show tun0 2>/dev/null | grep -q "inet "; then
  echo "no tun0 after 180 s"
  adb logcat -d | grep -iE "msnguard|aether|shard|vpn" | tail -60
  exit 1
fi

sleep 10
# The emulator image has no curl; toybox nc makes a plain HTTP request (DNS + TCP both go through the tunnel).
for i in 1 2 3 4 5 6; do
  code=$(adb shell "printf 'GET /generate_204 HTTP/1.1\r\nHost: connectivitycheck.gstatic.com\r\nConnection: close\r\n\r\n' | toybox nc -w 20 connectivitycheck.gstatic.com 80 | head -1" 2>/dev/null | tr -d '\r')
  echo "attempt $i: $code"
  if echo "$code" | grep -q " 204"; then
    echo "page loaded through the tunnel ✅"
    exit 0
  fi
  sleep 10
done
adb logcat -d | grep -iE "msnguard|aether|shard" | tail -60
exit 1
