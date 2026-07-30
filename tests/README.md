# Tests & Tools

This directory contains the diagnostic and fix scripts used during the
iAware investigation, plus reusable tools for future troubleshooting.

## Files

| File | Purpose |
|------|---------|
| `diagnose.sh` | Full diagnostic suite — checks iAware state, VPN, FCM, GMS, accounts, logs. Run this first. |
| `fix.sh` | Apply the iAware fix (disable `com.hihonor.iaware`). Reversible. |
| `unfix.sh` | Re-enable iAware (reverse of `fix.sh`). |
| `monitor.sh` | Live monitor of FCM/GMS connectivity through the VPN. |

## Quick start

```bash
# 1. Make sure your phone is connected via USB with debugging enabled
adb devices

# 2. Run the diagnostic (saves a timestamped report to test-results/)
./diagnose.sh test-results/diagnose-$(date +%Y%m%d-%H%M%S).txt

# 3. If the diagnostic reports iAware block is ACTIVE, apply the fix:
./fix.sh --reboot
# Wait for the phone to come back online

# 4. Re-run the diagnostic to confirm everything is green:
./diagnose.sh

# 5. (Optional) Watch FCM connectivity live:
./monitor.sh 5
```

## How the diagnostic decides pass/fail

The script checks 8 sections and reports OK / FAIL / WARN for each:

1. **ADB / Device** — is the phone reachable?
2. **iAware status** — is the Google block active? Cross-references the
   `persist.sys.iaware_google_conn` property with `pm list packages -d`
   to detect stale cached values (a disabled package means the property
   value is no longer authoritative).
3. **Region / SIM** — are the iAware trigger conditions present?
   (China SIM + CN hardware region + CN locale.)
4. **VPN / TUN** — is the VPN interface actually up?
5. **Direct connectivity** — can `curl` from the shell reach Google?
   (This bypasses the GMS framework, so it tests the network layer only.)
6. **FCM push channel** — is there a live TCP connection to
   `mtalk.google.com:5228/5229/5230`? This is the single most important
   check: if FCM is connected, Google push notifications will arrive.
7. **GMS / Play Store** — are the GMS and Play Store processes running?
8. **Google accounts** — is at least one Google account present on the device?

A PASS result means Google services should be working end-to-end.
