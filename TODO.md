# red-merle - TODO

## Done

### TAC prefixes aligned to modem frequency bands
Replaced the 16 generic blue-merle TAC prefixes with curated band-matched lists:
- `imei_prefix_ep06e`: 24 TACs for Mudi V1 (EP06-E, EMEA bands B1/B3/B5/B7/B8/B20/B28/B38/B40/B41)
- `imei_prefix_em060k`: 25 TACs for Mudi V2 (EM060K-GL, global bands)
- Sources: MiFi hotspots (Huawei, Netgear), Samsung Galaxy A/S global, iPhone global/US, Xiaomi, Pixel
- MiFi TACs prioritized (same device class as the Mudi = least suspicious network profile)

### Auto-detect modem variant (V1 EP06 vs V2 EM060K)
`detect_modem_prefixes()` sends `AT+CGMM` to identify the modem at runtime and selects the matching TAC list. Falls back to EP06-E list if unknown.

### Fix random.sample -> random.choices (entropy loss)
Replaced `random.sample(string.digits, 6)` (without replacement, 151,200 combinations, 17.2 bits) with `random.choices(string.digits, k=6)` (with replacement, 1,000,000 combinations, 19.9 bits). Eliminates the statistical fingerprint of all-distinct-digits serials.

### Fix validate_imei
Was checking for 14 digits, but IMEI is 15 digits (14 + Luhn check digit). Fixed to accept 15 digits + `isdigit()` validation.

### Wipe syslog/dmesg/history after IMEI change
- Removed `logger "Changed IMEI from X to Y"` calls that wrote IMEI history in cleartext to syslog
- Added `WIPE_LOGS()`: clears syslog ring buffer, dmesg, `~/.ash_history`, `/tmp/log/*`
- Runs at boot (clean up after crash), after each IMEI change, and at shutdown

### Disable carrier GPS tracking (LPP/SUPL/RRLP)
Added `DISABLE_CARRIER_GPS()`: sends `AT+QGPSCFG` commands to refuse carrier positioning requests. Runs at boot and after each IMEI change. Non-persistent on some Quectel firmware, hence re-applied every boot.

### DNS cache flush after IMEI change
Added `FLUSH_DNS()`: restarts dnsmasq after IMEI change to prevent session correlation via stale DNS entries.

### Automated release workflow
`.github/workflows/release.yml`: tag push triggers SDK build + offline install zip + GitHub release with both assets.

---

## To improve

### Expand TAC pool size
Currently 24-25 per modem variant. Target 50+ to reduce the probability of two red-merle users sharing the same TAC prefix on a given carrier. Requires additional TAC research and band verification.

### Mount /root/esim/ as tmpfs (like volatile-client-macs)
`shred` on `/root/esim/log.txt` does not reliably erase data on NAND flash due to wear leveling: the controller writes to a new physical block each time, leaving old data recoverable in spare blocks via chip-off or JTAG forensics. Current `shred` is a best-effort against software-level reads (`cat`, `strings`), not hardware forensics.

blue-merle solved this for the client MAC database (`/etc/oui-tertf`) by mounting it as tmpfs in `volatile-client-macs`, so the data never touches flash. But they did not apply the same treatment to `/root/esim/` - likely because the eSIM LPA (Local Profile Assistant) is a proprietary GL.iNet binary and it was unclear what data it writes there (the code comment says "unclear if the imei/imsi will be logged here, just a precaution").

The fix is straightforward: mount `/root/esim/` as tmpfs at boot, same pattern as `volatile-client-macs`. The `imei` file in that directory is just a cache for the GL.iNet web UI - the real IMEI is stored in the Quectel modem's internal flash (via `AT+EGMR`) and re-read at boot with `AT+GSN`. Losing `/root/esim/imei` on reboot has no functional impact.

Long-term: investigate full-disk encryption for OpenWrt on GL-E750.

### BSSID with real vendor OUI
Current `UNICAST_MAC_GEN()` generates fully random MACs. A BSSID whose first 3 bytes (OUI) don't match any known manufacturer in the IEEE database is a fingerprinting signal for anyone scanning WiFi networks.
- Maintain a list of common vendor OUIs (Samsung, Apple, Intel, Qualcomm, etc.)
- Pick a random OUI from the list, randomize the remaining 3 bytes

---

## To do

### Band-lock modem to match spoofed TAC
After setting a spoofed IMEI, restrict the modem to only connect on bands that the spoofed device supports. Eliminates band mismatch fingerprinting entirely (currently mitigated by TAC selection, but not eliminated).
- `AT+QCFG="band"` to configure allowed bands
- Maintain TAC -> band mapping table
- Restore full bands on next IMEI change

### Deterministic mode: ICCID instead of IMSI
Current deterministic mode seeds the PRNG with IMSI (`AT+CIMI`), which fails on PIN-locked SIMs. ICCID (`AT+CCID`) is always available without PIN.
- Switch seed source to ICCID
- Keep backward compatibility option for existing users

### Panic button
Emergency action: wipe IMEI (`AT+EGMR=1,7,"000000000000000"`), wipe all logs, clear history, poweroff.
- Bind to hardware toggle (long-press 5s or triple-press pattern to distinguish from normal SIM swap toggle)
- Display confirmation on OLED
- Mudi V2 has a different button layout - investigate available buttons

### Remove Python dependency
Replace `imei_generate.py` (210 lines) with pure ash/lua using `gl_modem AT` for serial communication. Reduces package size and boot time. Significant rewrite effort.

### Rayhunter integration (IMSI catcher detection)
Integrate EFF's Rayhunter project to detect fake base stations. Requires a daemon monitoring modem baseband messages. Significant standalone effort, separate from the core IMEI/MAC anonymization features.
