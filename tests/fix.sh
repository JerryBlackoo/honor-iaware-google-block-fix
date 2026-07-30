#!/usr/bin/env bash
# =============================================================================
# fix.sh — Apply the iAware Google-block fix on a Honor phone
# =============================================================================
# Disables com.hihonor.iaware so that GMS / FCM traffic can reach the VPN
# instead of being blocked at the Android application-framework layer.
#
# Usage:   ./fix.sh [--reboot]
#          --reboot   automatically reboot the device after disabling
#                     (the fix only takes full effect after a reboot)
#
# Requirements:
#   - adb in PATH, phone connected with USB debugging
#   - The fix is REVERSIBLE — see unfix.sh
# =============================================================================
set -u

AUTO_REBOOT=0
[ "${1:-}" = "--reboot" ] && AUTO_REBOOT=1

echo "Honor iAware Google-block fix"
echo "============================="

# Pre-check: is the block even active?
PROP="$(adb shell getprop persist.sys.iaware_google_conn 2>/dev/null | tr -d '\r')"
ALREADY_DISABLED="$(adb shell pm list packages -d 2>/dev/null | grep -c 'com.hihonor.iaware')"
echo "Current iaware_google_conn = ${PROP:-(empty)}"
echo "iAware already disabled?   $([ "$ALREADY_DISABLED" -ge 1 ] && echo yes || echo no)"
echo ""

if [ "$ALREADY_DISABLED" -ge 1 ]; then
  echo "iAware is already disabled. No action needed."
  echo "If Google services still fail, try:"
  echo "  1. Reboot the phone (the disable needs a reboot to fully take effect)"
  echo "  2. Run ./diagnose.sh to check the actual state"
  exit 0
fi

# Confirm the package exists
PKG_EXISTS="$(adb shell pm list packages 2>/dev/null | grep -c 'com.hihonor.iaware')"
if [ "$PKG_EXISTS" -eq 0 ]; then
  echo "ERROR: com.hihonor.iaware not found on this device."
  echo "This fix only applies to Honor / Huawei devices with the iAware service."
  exit 1
fi

echo "Disabling com.hihonor.iaware for user 0..."
adb shell pm disable-user --user 0 com.hihonor.iaware
RC=$?
if [ $RC -ne 0 ]; then
  echo "ERROR: pm disable-user failed (exit $RC)."
  echo "Make sure USB debugging is enabled and the PC is authorized."
  exit $RC
fi
echo "Done. Package is now in disabled state."
echo ""

# Side-effect warning
echo "NOTE: iAware also manages battery optimization / app launch management."
echo "      Disabling it may slightly reduce aggressive battery management."
echo "      In practice the impact is negligible for normal use."
echo ""

if [ "$AUTO_REBOOT" -eq 1 ]; then
  echo "Rebooting device (auto)..."
  adb reboot
  echo "Wait for the phone to come back online, then run ./diagnose.sh to verify."
else
  echo "IMPORTANT: Reboot the phone now for the fix to take full effect."
  echo "  adb reboot"
  echo ""
  echo "After reboot, verify with:"
  echo "  ./diagnose.sh"
fi
