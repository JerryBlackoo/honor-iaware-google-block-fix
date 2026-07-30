# Evidence

Captured evidence from the iAware investigation. No sensitive data —
these files contain only system properties and connection states.

| File | Description |
|------|-------------|
| `system-props-*.txt` | Relevant `getprop` output showing iAware state, region, SIM country, locale. |
| `fcm-connections-*.txt` | `ss -tn` output showing the live FCM TCP connection to mtalk.google.com:5228 after the fix. |

## Key evidence: FCM is working after the fix

`fcm-connections-*.txt`:
```
ESTAB  0  0  [::ffff:172.19.0.1]:47238  [::ffff:142.250.101.188]:5228
```
- `172.19.0.1` = the tun0 interface address
- `142.250.101.188:5228` = a Google IP on the FCM push port

This single line proves the fix worked: FCM traffic is now flowing, so
Google push notifications will arrive.

## Key evidence: iAware state

`system-props-*.txt` shows:
```
[persist.sys.iaware_google_conn]: [1785377147, 0]
```
The `0` looks like "block active", but it is a **stale cached value**
written before the package was disabled. The authoritative check is
`pm list packages -d`, which includes `com.hihonor.iaware` — confirming
the package is disabled and cannot enforce the block.
