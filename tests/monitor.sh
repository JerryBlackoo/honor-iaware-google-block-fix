#!/usr/bin/env bash
# =============================================================================
# monitor.sh — Live monitor of FCM / GMS connectivity through the VPN
# =============================================================================
# Watches the FCM push channel (mtalk.google.com:5228) and the Clash API
# connection list in real time. Useful to confirm that GMS traffic is
# actually flowing through the VPN after applying the iAware fix.
#
# Usage:   ./monitor.sh [interval_seconds]
#          default interval = 5s. Ctrl-C to stop.
# =============================================================================
set -u
INTERVAL="${1:-5}"

echo "Live FCM / GMS monitor (every ${INTERVAL}s). Ctrl-C to stop."
echo "Columns: time | tun state | FCM conn | VPN conns | GMS proc"
echo "----------------------------------------------------------------"

while true; do
  TS="$(date '+%H:%M:%S')"
  TUN="$(adb shell "ip -o addr show tun0 2>/dev/null | grep -c 'inet '" | tr -d '\r')"
  MTALK="$(adb shell "ss -tn 2>/dev/null | grep -cE ':5228|:5229|:5230'" | tr -d '\r')"
  CONNS="$(adb shell "curl -s --max-time 2 http://127.0.0.1:9090/connections 2>/dev/null | grep -o '\"id\"' | wc -l" | tr -d '\r')"
  GMS="$(adb shell "pgrep -f com.google.android.gms 2>/dev/null | head -1" | tr -d '\r')"
  [ -z "$GMS" ] && GMS="-"
  printf "%s | tun=%s | fcm=%s | vpn_conns=%s | gms_pid=%s\n" \
    "$TS" "$TUN" "$MTALK" "$CONNS" "$GMS"
  sleep "$INTERVAL"
done
