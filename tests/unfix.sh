#!/usr/bin/env bash
# =============================================================================
# unfix.sh — Re-enable iAware (reverse of fix.sh)
# =============================================================================
# Re-enables com.hihonor.iaware. Useful if you sell the phone, return it
# for warranty, or want to restore default battery management behavior.
#
# Usage:   ./unfix.sh [--reboot]
# =============================================================================
set -u

AUTO_REBOOT=0
[ "${1:-}" = "--reboot" ] && AUTO_REBOOT=1

echo "Re-enabling com.hihonor.iaware..."
adb shell pm enable com.hihonor.iaware
RC=$?
if [ $RC -ne 0 ]; then
  echo "ERROR: pm enable failed (exit $RC)."
  exit $RC
fi
echo "iAware re-enabled. After reboot the Google block will be active again"
echo "(if China SIM + CN region conditions are met)."
echo ""
if [ "$AUTO_REBOOT" -eq 1 ]; then
  adb reboot
else
  echo "Reboot to apply: adb reboot"
fi
