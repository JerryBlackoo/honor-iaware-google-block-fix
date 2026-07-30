#!/usr/bin/env bash
# =============================================================================
# diagnose.sh — Honor iAware / Google connectivity diagnostic suite
# =============================================================================
# Purpose: Verify whether the phone can reach Google services properly,
#          and identify whether iAware (or similar framework-layer
#          interception) is blocking GMS traffic.
#
# Usage:   ./diagnose.sh [output_file]
#          If output_file is omitted, prints to stdout.
#
# Requirements:
#   - adb in PATH
#   - Phone connected via USB (or wireless ADB) with USB debugging enabled
#   - A VPN client running with a Clash-compatible API on 127.0.0.1:9090
#     (optional — tests gracefully skip if API is not reachable)
#
# Exit codes:
#   0  = all critical checks passed
#   1  = one or more critical checks failed
#   2  = adb / device not available
# =============================================================================
set -u

OUT="${1:-/dev/stdout}"
TMP="$(mktemp)"
exec > >(tee "$TMP") 2>&1
trap 'cp "$TMP" "$OUT" 2>/dev/null || true; rm -f "$TMP"' EXIT

PASS=0
FAIL=0
WARN=0
SECTION() { printf "\n\033[1;36m=== %s ===\033[0m\n" "$1"; }
OK()   { printf "  \033[32m[ OK ]\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
BAD()  { printf "  \033[31m[FAIL]\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
WARN() { printf "  \033[33m[WARN]\033[0m %s\n" "$1"; WARN=$((WARN+1)); }
INFO() { printf "  \033[90m[info]\033[0m %s\n" "$1"; }

echo "Honor iAware / Google Connectivity Diagnostic"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Host: $(hostname)"

# ---------------------------------------------------------------------------
SECTION "0. ADB / Device"
# ---------------------------------------------------------------------------
if ! command -v adb >/dev/null 2>&1; then
  BAD "adb not found in PATH"
  exit 2
fi
OK "adb found: $(command -v adb)"

DEVICES="$(adb devices 2>/dev/null | grep -c 'device$')"
if [ "$DEVICES" -eq 0 ]; then
  BAD "no adb device connected"
  exit 2
fi
OK "$DEVICES device(s) connected"

MODEL="$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
BUILD="$(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')"
ANDROID="$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
INFO "Device: $MODEL / Android $ANDROID / $BUILD"

# ---------------------------------------------------------------------------
SECTION "1. iAware status (the root cause)"
# ---------------------------------------------------------------------------
IAWARE_PROP="$(adb shell getprop persist.sys.iaware_google_conn 2>/dev/null | tr -d '\r')"
# Check if iAware package is disabled FIRST — a disabled package means the
# property value is stale (cached before disable) and the block is NOT active.
IAWARE_DISABLED="$(adb shell pm list packages -d 2>/dev/null | grep -c 'com.hihonor.iaware')"
IAWARE_ENABLED="$(adb shell pm list packages 2>/dev/null | grep -c 'com.hihonor.iaware')"

if [ -z "$IAWARE_PROP" ] || [ "$IAWARE_PROP" = "" ]; then
  WARN "iaware_google_conn property is empty (iAware may not exist on this device)"
else
  INFO "persist.sys.iaware_google_conn = $IAWARE_PROP"
  # Format: [timestamp, state]  state: 0=blocked, 1=allowed
  STATE="$(echo "$IAWARE_PROP" | sed -E 's/.*,\s*([0-9]).*/\1/')"
  TS="$(echo "$IAWARE_PROP" | sed -E 's/\[\s*([0-9]+).*/\1/')"
  if [ -n "$TS" ] && [ "$TS" -gt 0 ] 2>/dev/null; then
    TS_HUMAN="$(adb shell "date -d @$TS '+%Y-%m-%d %H:%M:%S %Z'" 2>/dev/null | tr -d '\r')"
    INFO "iAware trigger timestamp: $TS → $TS_HUMAN"
  fi

  # The property is just a cached flag. The REAL authority is whether the
  # iAware package is running. A disabled package cannot enforce the block,
  # so a state=0 with a disabled package is a STALE value, not an active block.
  if [ "$IAWARE_DISABLED" -ge 1 ]; then
    if [ "$STATE" = "0" ]; then
      WARN "Property shows state=0 BUT com.hihonor.iaware is DISABLED → stale cached value, block NOT active"
    else
      OK "iAware block INACTIVE (state=1) and package disabled"
    fi
  elif [ "$IAWARE_ENABLED" -ge 1 ]; then
    if [ "$STATE" = "0" ]; then
      BAD "iAware Google block is ACTIVE (state=0, package enabled). GMS traffic blocked at framework layer."
      INFO "  Fix: adb shell pm disable-user --user 0 com.hihonor.iaware && reboot"
    elif [ "$STATE" = "1" ]; then
      OK "iAware Google block is INACTIVE (state=1, package enabled)"
    else
      WARN "iAware state unclear: '$STATE'"
    fi
  else
    INFO "com.hihonor.iaware package not found (non-Honor device?)"
  fi
fi

if [ "$IAWARE_DISABLED" -ge 1 ]; then
  OK "com.hihonor.iaware is DISABLED (pm list packages -d)"
elif [ "$IAWARE_ENABLED" -ge 1 ]; then
  WARN "com.hihonor.iaware is ENABLED. If Google services fail, disable it:"
  INFO "  adb shell pm disable-user --user 0 com.hihonor.iaware && reboot"
fi

# ---------------------------------------------------------------------------
SECTION "2. Region / SIM detection (iAware trigger conditions)"
# ---------------------------------------------------------------------------
SIM_COUNTRY="$(adb shell getprop gsm.sim.operator.iso-country 2>/dev/null | tr -d '\r')"
HW_COUNTRY="$(adb shell getprop ro.hw.country 2>/dev/null | tr -d '\r')"
LOCALE_REGION="$(adb shell getprop ro.product.locale.region 2>/dev/null | tr -d '\r')"
SYS_LOCALE="$(adb shell getprop persist.sys.locale 2>/dev/null | tr -d '\r')"
GOOGLE_NLP="$(adb shell getprop sys.show_google_nlp 2>/dev/null | tr -d '\r')"

INFO "gsm.sim.operator.iso-country = $SIM_COUNTRY"
INFO "ro.hw.country = $HW_COUNTRY"
INFO "ro.product.locale.region = $LOCALE_REGION"
INFO "persist.sys.locale = $SYS_LOCALE"
INFO "sys.show_google_nlp = $GOOGLE_NLP"

CN_HITS=0
echo "$SIM_COUNTRY" | grep -qi cn && CN_HITS=$((CN_HITS+1))
[ "$HW_COUNTRY" = "cn" ] && CN_HITS=$((CN_HITS+1))
[ "$LOCALE_REGION" = "CN" ] && CN_HITS=$((CN_HITS+1))
if [ "$CN_HITS" -ge 2 ]; then
  WARN "China region detected ($CN_HITS/3 signals). iAware Google block would trigger if enabled."
else
  OK "China region NOT strongly detected ($CN_HITS/3 signals)."
fi

# ---------------------------------------------------------------------------
SECTION "3. VPN / TUN interface"
# ---------------------------------------------------------------------------
VPN_STATE="$(adb shell dumpsys connectivity 2>/dev/null | grep -A2 'Active default VPN' | head -3)"
# Use `ip -o link show` and check flags for UP — more robust than `ip addr show`
# which on some Android shells appends a stray '\r' that breaks grep.
TUN_FLAGS="$(adb shell "ip -o link show tun0 2>/dev/null" | tr -d '\r')"
TUN_EXISTS="$(adb shell "ip -o addr show tun0 2>/dev/null | grep -c 'inet '" | tr -d '\r')"
if echo "$TUN_FLAGS" | grep -q ',UP,' || [ "$TUN_EXISTS" -ge 1 ]; then
  OK "tun0 interface is UP"
  TUN_ADDR="$(adb shell "ip -o addr show tun0 2>/dev/null | grep 'inet ' | awk '{print \$4}'" | tr -d '\r')"
  INFO "tun0 address: $TUN_ADDR"
else
  BAD "tun0 interface is DOWN or missing — VPN not running?"
fi

if [ -n "$VPN_STATE" ]; then
  INFO "VPN state: $VPN_STATE"
else
  WARN "Could not read VPN state from dumpsys connectivity"
fi

# ---------------------------------------------------------------------------
SECTION "4. Direct connectivity from shell (bypasses GMS framework)"
# ---------------------------------------------------------------------------
test_url() {
  local url="$1"
  local label="$2"
  local code
  code="$(adb shell "curl -s -o /dev/null -w '%{http_code}' --max-time 10 '$url'" 2>/dev/null | tr -d '\r')"
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
    OK "$label → HTTP $code (reachable from shell)"
  elif [ -n "$code" ] && [ "$code" != "000" ]; then
    WARN "$label → HTTP $code"
  else
    BAD "$label → unreachable (curl returned '$code')"
  fi
}
test_url "https://www.google.com"              "www.google.com       "
test_url "https://play.google.com"            "play.google.com      "
test_url "https://accounts.google.com"        "accounts.google.com  "
test_url "https://connectivitycheck.gstatic.com/generate_204" "connectivitycheck   "
test_url "https://www.baidu.com"              "www.baidu.com (control)"

# ---------------------------------------------------------------------------
SECTION "5. FCM push channel (mtalk.google.com:5228)"
# ---------------------------------------------------------------------------
# FCM uses raw TCP on 5228, not HTTPS. Check if a connection exists.
MTALK_CONN="$(adb shell "ss -tn 2>/dev/null | grep -E ':5228|:5229|:5230' | head -5" | tr -d '\r')"
if [ -n "$MTALK_CONN" ]; then
  OK "FCM TCP connection found (mtalk:5228/5229/5230):"
  echo "$MTALK_CONN" | sed 's/^/      /'
else
  WARN "No FCM TCP connection to mtalk.google.com:5228/5229/5230"
  INFO "  This means Google push notifications will NOT arrive."
  INFO "  If iAware is active, it blocks this channel at the framework layer."
fi

# Also check via Clash API if available
CLASH_CONNS="$(adb shell "curl -s --max-time 3 http://127.0.0.1:9090/connections" 2>/dev/null | tr -d '\r')"
if [ -n "$CLASH_CONNS" ] && echo "$CLASH_CONNS" | grep -q '"connections"'; then
  MTALK_IN_CLASH="$(echo "$CLASH_CONNS" | grep -o 'mtalk[^"]*' | head -3)"
  if [ -n "$MTALK_IN_CLASH" ]; then
    OK "FCM (mtalk) traffic IS flowing through the VPN proxy"
    echo "$MTALK_IN_CLASH" | sed 's/^/      /'
  else
    WARN "No mtalk.google.com connection in Clash/ClashAPI connections list"
    INFO "  → GMS traffic is NOT reaching the VPN. Framework-layer block likely."
  fi
  # Count total connections
  CONN_COUNT="$(echo "$CLASH_CONNS" | grep -o '"id"' | wc -l)"
  INFO "Total active connections through VPN: $CONN_COUNT"
else
  INFO "Clash API not reachable on 127.0.0.1:9090 (skipping connection-list check)"
fi

# ---------------------------------------------------------------------------
SECTION "6. GMS / Play Store processes"
# ---------------------------------------------------------------------------
GMS_PID="$(adb shell "pgrep -f com.google.android.gms 2>/dev/null" | tr -d '\r' | head -1)"
PLAY_PID="$(adb shell "pgrep -f com.android.vending 2>/dev/null" | tr -d '\r' | head -1)"
if [ -n "$GMS_PID" ]; then
  OK "Google Play Services running (pid=$GMS_PID)"
else
  WARN "Google Play Services NOT running"
fi
if [ -n "$PLAY_PID" ]; then
  OK "Play Store running (pid=$PLAY_PID)"
else
  INFO "Play Store not running (may just be closed)"
fi

# ---------------------------------------------------------------------------
SECTION "7. Google accounts on device"
# ---------------------------------------------------------------------------
ACCTS="$(adb shell "dumpsys account 2>/dev/null | grep -A1 'com.google' | head -10" | tr -d '\r')"
if [ -n "$ACCTS" ]; then
  OK "Google accounts present on device:"
  echo "$ACCTS" | sed 's/^/      /'
else
  WARN "No Google accounts found (or could not read dumpsys account)"
fi

# ---------------------------------------------------------------------------
SECTION "8. Recent GMS / FCM log errors"
# ---------------------------------------------------------------------------
LOG_ERRORS="$(adb shell "logcat -d -t 100 2>/dev/null | grep -iE 'gms|firebase|fcm|mtalk' | grep -iE 'error|fail|refus|timeout' | tail -5" | tr -d '\r')"
if [ -n "$LOG_ERRORS" ]; then
  WARN "Recent GMS/FCM errors in logcat:"
  echo "$LOG_ERRORS" | sed 's/^/      /'
else
  OK "No recent GMS/FCM errors in logcat (last 100 lines)"
fi

# ---------------------------------------------------------------------------
SECTION "Summary"
# ---------------------------------------------------------------------------
echo ""
printf "  Passed: \033[32m%d\033[0m   Failed: \033[31m%d\033[0m   Warnings: \033[33m%d\033[0m\n" "$PASS" "$FAIL" "$WARN"
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "  \033[32mRESULT: PASS — Google services appear to be working.\033[0m"
  exit 0
else
  echo "  \033[31mRESULT: FAIL — see failures above. Likely iAware or VPN issue.\033[0m"
  exit 1
fi
