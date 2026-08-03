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

### Stealth-aware boot: skip modem wait when no AT hardening is planned
init.d `start()` only launches the `WAIT_FOR_MODEM` + GPS-hardening subshell when `hardening_mode` is `hardening`. In the default stealth mode there is no AT activity by design, so boot does not wait and the OLED never claims GPS success it did not perform.

### red-merle-ctl control utility
New `/usr/bin/red-merle-ctl`: full status dashboard (modem, IMEI, IMSI, own number via AT+CNUM, SIM, registration, signal, network, modes, SUPL block), granular `lte-only on|off` flag independent of hardening mode, `gps on|off`, `hardening on|off` (apply/revert immediately), IMEI show/random/deterministic/set, SMS list/read/send (Ctrl-Z terminated via direct TTY write)/delete, signal details, one-shot `revert`, and an interactive menu when called without arguments. Package version bumped to 2.2.0.

### Revert path for persistent AT settings + SMS/call documentation
`nwscanmode`/`mode_pref`/`ims` are stored in the modem's NV memory and survive reboots. `REVERT_CARRIER_HARDENING()` restores them (all RATs + IMS on, XTRA back to the family default); `red-merle-mode-switch stealth` calls it automatically, and `hardening` now applies the AT suite immediately instead of waiting for a reboot. README documents the connectivity matrix: SMS keeps working via SMS-over-SGs (standard LTE path), voice calls are impossible in hardening mode, first SIM registration is unaffected.

### AT suite verified against official Quectel documentation
Cross-checked every hardening command against the Quectel LTE-A(Q) Series GNSS Application Note V1.1 and the EG06xK&Ex120K&EM060K AT Commands Manual. Corrections: `lppe` and `suplssl` QGPSCFG items do not exist on the LTE-A(Q) series (LPP is disabled via `agnssprotocol`, SUPL via the port-7275 iptables block), `AT+QGPS=0` dropped (QGPSEND is the off switch), EM060K `mode_pref` takes string values (`LTE`, not `2`). Also added `AT+QGPSXTRA=0` — XTRA assistance phones home to Qualcomm izatcloud servers and is enabled by default on EM060K. Remaining to confirm on hardware: exact `agnssprotocol` parameter form.

### IMEI generator robustness
`-s <imei> -g` (static + generate-only) no longer writes to the modem, and serial failures (modem absent/unplugged) exit cleanly with code 2 and a clear stderr message instead of a Python traceback. Exit codes verified: 0 ok, 255 invalid IMEI, 2 modem error. Validated offline: 200 generated IMEIs all Luhn-valid, TACs uniformly drawn from the EP06-E list, digit repetition present in serials (entropy fix confirmed).

### Automated release workflow
`.github/workflows/release.yml`: tag push triggers SDK build + offline install zip + GitHub release with both assets.

### Boot-time GPS hardening gate
At START=10 the Quectel modem is not up, so `DISABLE_CARRIER_GPS` silently no-oped while the OLED claimed success. Added `WAIT_FOR_MODEM()` (30 tries x 2s) in functions.sh; init.d `start()` now runs GPS hardening in a backgrounded subshell after the fast boot work, prints `[OK] GPS hardened` only on success, and on timeout prints `[..] GPS deferred` and leaves `/tmp/red-merle-gps-deferred` (retried on next `red-merle` invocation).

### Fix Quectel AT commands
Corrected `AT+QGPSCFG="lppe",0,0` to `"lppe",0`, replaced the bogus `AT+QNWPREFMDE=38` with per-modem LTE preference (`AT+QCFG="nwscanmode",3,1` on EP06/EC25, `AT+QNWPREFCFG="mode_pref",2` on EM060K/EM05). Responses are captured via `AT_SEND` and logged to `/tmp/red-merle-at.log` instead of being swallowed by `2>/dev/null`. NOTE: AT commands still need on-hardware validation on a real Mudi.

### Modem detection extended to Mudi V2
`DETECT_MODEM_TTY` regex now matches EM060K/EM05 (not only EC25/EP06); fixed inverted V1/V2 comment (V1 = EP06-E, V2 = EM060K-GL).

### Default hardening mode aligned to stealth
`files/etc/config/red-merle` now defaults `hardening_mode` to `stealth` (README recommendation), matching the `GET_HARDENING_MODE` fallback. Hardening remains available via UCI / `red-merle-mode-switch`.

### Idempotent iptables blocking
`SETUP_IPTABLES_BLOCKING` uses `iptables -C || iptables -I`, writes `/etc/firewall.d/red-merle-blocking` only once, and documents that blocking UDP/TCP 4500 kills IPsec NAT-T passthrough (deliberate trade-off).

### Postinst enables init services (no-SDK build)
build.sh postinst now runs `/etc/init.d/red-merle enable` and `/etc/init.d/volatile-client-macs enable`; `/etc/config/red-merle` declared as conffile in both build.sh and the Makefile. Version unified at 2.1.0.

### Dead code removal
Removed `GENERATE_IMEI`, `SET_IMEI`, `DETECT_MODEM`, `luhn.lua`, the `config imei` seed section, the broken `write-imei` libexec branch, and the stale `files/etc/init.d/red-merle.orig` duplicate. `FLUSH_DNS` no longer `killall`s dnsmasq; shutdown path no longer runs `DISABLE_CARRIER_GPS`.

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

### Validated on real hardware (GL-E750 V2, EM060K-GL, firmware EM060KGLAAR01A11M2G)
Full hardening suite passes on-device: `agnssprotocol`, `agpsposmode`, `QGPSXTRA=0`, `gpsnmeatype`, `ims`, `mode_pref",LTE"` all return OK; revert restores AUTO/ims/XTRA. Fixes from on-device testing: dropped `suplver",0"` (CME 501 — 0 is not a valid SUPL version), tolerate QGPSEND CME 505 (GNSS already off), model detection now via `gl_modem AT+CGMM` (raw TTY probing raced gl_modem's port usage), TTY probe rewritten with `read -t` (no more killed `cat` noise). `red-merle-ctl` dashboard, lte-only on/off round-trip, SUPL iptables block all confirmed working.

### LuCI themes + GL panel theme + branded banner
New `luci-theme-red-merle` package (themes/): two full LuCI themes — `redmerle` (dark red) and `redmerle-hacker` (green CRT phosphor) — selectable in System → Language & Style. Main package now also ships a GL 4.x admin panel theme (`/www/theme/redmerle`, red palette) registered in the home i18n files via python3 in postinst (busybox sed proved unreliable on the pretty-printed JSON), and brands the SSH banner `OpenWrt ... — ☢ red-merle <version>` idempotently.

### GL panel theme dropdown entry
The GL 4.x panel hardcodes its theme list in the minified home view JS (`gl-sdk4-ui-home.common.js.gz`). postinst now patches the bundle (gzip-safe, idempotent, verified count==1 before replacing) so "Red Merle" appears in the palette dropdown next to Classic/Dark. Firmware upgrades will revert the JS — reinstalling red-merle re-applies.

### redmerle-hacker GL panel theme
Second GL 4.x panel theme (green phosphor palette) shipped next to redmerle; postinst JS patch now injects both dropdown entries, i18n registration covers both labels in all 10 languages.

### Fix gl_clients crash loop after reboot (upstream blue-merle bug)
`volatile-client-macs` stop() shredded client.db WITHOUT --remove, leaving a garbage-filled file that the next boot propagated into the tmpfs; gl_clients_update then crash-looped on the invalid sqlite file and the Clients page showed 0 entries forever. stop() now shred+removes, and start() only propagates the database if it has a valid "SQLite format 3" header. Validated by reboot: daemon alive, tmpfs mounted, fresh valid DB, zero crashes. Upstream bug, present in blue-merle as well.

### Configurable boot behaviors (UCI + red-merle-ctl config)
Every boot behavior is now individually toggleable via UCI options in `/etc/config/red-merle` (all default to 1 = classic behavior): `wipe_logs`, `randomize_mac`, `randomize_bssid`, `iptables_block`, `gps_hardening`. New `GET_CONFIG_OPTION <name> <default>` helper in functions.sh (modeled on `GET_HARDENING_MODE`). `WIPE_LOGS`, `SETUP_IPTABLES_BLOCKING`, `RANDOMIZE_MACADDR`, `RESET_BSSIDS` no-op when their option is 0, which covers every call site (init.d, `/usr/bin/red-merle`, stage1/stage2 toggle scripts, libexec, and the `SETUP_IPTABLES_BLOCKING` call inside `DISABLE_CARRIER_GPS`). init.d `start()` gates each step and the OLED summary now honestly shows `[OK]`/`[OFF]` per item; `gps_hardening 0` skips the backgrounded AT suite even in hardening mode; `stop()` only wipes when `wipe_logs` is on. `red-merle-ctl config` lists all options with meanings, `red-merle-ctl config <name> on|off` sets via uci + commit (name validated, accepts 1/0/on/off), added to the interactive menu (`c`) and usage text; `status` shows a compact `Boot opts: logs✓ mac✓ bssid✓ iptables✓ gps✓` line. Version bumped to 2.3.0.

### Configurable boot behaviors + GL panel branding (v2.3.0)
All boot steps (wipe_logs, randomize_mac, randomize_bssid, iptables_block, gps_hardening) are now UCI options, gated inside functions.sh so every caller (init.d, CLI, toggle stages) respects them; `red-merle-ctl config` lists/toggles them, status shows their state, OLED reports [OFF] steps. Package also brands the GL panel: combined GL.iNet + ☢ logo (shipped via /usr/share to avoid the opkg file clash with gl-sdk4-ui-core, copied by postinst), header link with version, RED MERLE sidebar entry to the LuCI page — all injected into index.html idempotently.

### LuCI control dashboard (full status/controls/boot options/AT log)
The LuCI page (`files/www/luci-static/resources/view/red-merle.js`) is now a full dashboard on the LuCI 22.03 client-side view API: a Status card (modem model, firmware, IMEI, IMSI, own number, SIM, registration, signal, network, hardening mode, LTE-only, GNSS, SUPL block — auto-loaded on view load, with Refresh), a Controls card (hardening / LTE-only / GNSS on-off with live state and notifications), a Boot options card (the 5 UCI options as clickable toggles), the original SIM swap flow kept intact (same buttons and libexec calls), and an AT log card (last 40 lines of /tmp/red-merle-at.log in a monospace view). Native LuCI markup only (cbi-section / cbi-value / table / btn), no external CSS.
The rpcd backend (`files/usr/libexec/red-merle`) gained JSON actions next to the untouched legacy ones (read-imei, read-imsi, random-imei, shutdown, shutdown-modem keep byte-identical output): `status` (single JSON object, reusing the red-merle-ctl query logic via functions.sh; no jq on busybox — printf emission with whitelist sanitization of AT-derived values), `set-option <name> <0|1>` (validated against the 5 boot options, uci set + commit), `lte-only|gps|hardening on|off` (same AT semantics as red-merle-ctl), and `at-log` (JSON array of the last 40 log lines). All actions idempotent. ACL extended with explicit grants for the new actions. Verified locally with `tests/run-dashboard-tests.sh`: stubbed gl_modem/uci/iptables, every action's output proven to parse as JSON (python3 json.loads) with all required keys, sanitization proven against hostile quotes/backslashes in AT replies, legacy action output formats confirmed unchanged.

### GL-native dashboard (v2.5.0)
/redmerle/ — a self-contained control page served inside the GL admin panel look (follows the active panel theme via localStorage like the GL app): status grid, hardening/LTE-only/GNSS toggles, boot options, random IMEI, AT log viewer. Backed by /cgi-bin/redmerle-api, a shell bridge that validates the Admin-Token cookie against gl-session before running libexec actions (403 without a valid session). The RED MERLE sidebar entry now opens this page instead of LuCI; the LuCI dashboard remains available as the advanced UI. Also v2.4.1: SIM swap modal gains Restart modem and Close buttons.

### SIM swap in the GL dashboard, eSIM IMEI leak, self-healing versions (v2.6.0)
`/redmerle/` answered **403 Forbidden**: the GL panel sets a global `index gl_home.html`, so a request for the directory looked for a file that only exists at `/www/`, and with autoindex off nginx refused. Fixed with an `/etc/nginx/gl-conf.d/red-merle.conf` drop-in (`index index.html` + the same `access_by_lua_file` hook `location /` carries, so the https redirect still applies). The postinst validates the drop-in with `nginx -t` and pulls it back out if nginx rejects it, rather than risk a dead panel at the next restart. Reloading needed a real `kill -HUP` on the master: this firmware's init script ships **no reload action**, so `/etc/init.d/nginx reload` is a silent no-op.

**Forensic leak fixed**: GL's eSIM LPA daemon caches the IMEI it last saw in `/root/esim/imei` and logs to `/root/esim/log.txt`, both surviving reboots. Only `usr/bin/red-merle` and `switch-stage2` refreshed that file, so changing the IMEI from `red-merle-ctl`, the LuCI dashboard or the GL dashboard left a plaintext copy of the *previous* — often factory — IMEI on disk while the modem reported a spoofed one. Proven live: modem `3533221…` (a red-merle TAC) vs `/root/esim/imei` `3539771…` (a TAC absent from every pool). The sync now happens in `imei_generate.py:set_imei()`, the single choke point every path goes through, with the file forced back to mode 0600 and the log shredded (plain-overwrite fallback if `shred` is missing). `WIPE_LOGS` also shreds that log at boot.

All user-visible version strings now come from one source. The postinst hands `PKG_VERSION` to `usr/share/red-merle/patch-branding.py`, a shipped script that rewrites the SSH banner, the panel header and the System Info row on **every** install — previously each was written once and then skipped, so a router upgraded from 2.2.0 kept announcing 2.2.0 forever. Replacing the inline heredoc python with a real file also retired the whole `$`-escaping minefield. On the repository side, `scripts/bump-version.sh` rewrites every occurrence (Makefile, build.sh, README, website) and `tests/check-version.sh` fails CI when one drifts; the release workflow additionally refuses a tag that does not match `PKG_VERSION`. It immediately caught the website advertising v2.5.0 while its install snippet still said 2.3.0.

SSH banner now shows RED MERLE ASCII art above the stock OpenWrt logo (both kept), self-healing so reinstalls never stack it. The GL dashboard gained the **SIM swap flow** it was missing next to LuCI (shutdown-modem → random IMEI → swap prompt → restart/shutdown/close), with `shutdown` and `shutdown-modem` added to the CGI whitelist. Failed API calls used to leave the page on "loading…" behind a 2.6s toast; they now say so in place, with a login link when the panel session expired. `red-merle-ctl` gained `help`/`-h`/`--help`, `version`/`-V`, `--flag` aliases for every command, a non-zero exit on unknown commands and a pointer to the CLI from the interactive menu. Fixed the injected header divider sticking to "v4.0" (the stock `.divide-left` only carries a right margin) and CJK languages rendering as empty boxes in the hacker theme (its monospace stack has no CJK glyphs — added per-glyph fallbacks).

### Full SIM swap on the web, eSIM daemon control, live control states (v2.7.0)
The CGI bridge never printed a header block on its success paths — it piped the libexec's bare output straight to stdout. A CGI response without `Content-type:` and a blank line is malformed, so nginx answered with an HTML error page and the browser reported `JSON.parse: unexpected character at line 1 column 1`. **The GL dashboard had therefore never worked while logged in**; only the 403 branch emitted correct headers, which made it look like a session problem. Every exit path now emits headers, proven per action (`application/json` for the JSON actions, `text/plain` for the legacy bare-text ones).

The web SIM swap was a truncated copy of the CLI flow: it did `AT+CFUN=4`, one IMEI, then stopped. It skipped the `CFUN=0`/`CFUN=4` reset cycle, the IMSI change check, the **second** IMEI pass (mandatory in deterministic mode, which seeds on the *new* IMSI), and the whole `WIPE_LOGS` + `DISABLE_CARRIER_GPS` + `FLUSH_DNS` cleanup. New libexec action `sim-swap begin|finish [random|deterministic]` replays the complete CLI sequence server-side with bounded retries (a web request must not loop forever like the interactive CLI does), reports `slow_reset` when the reset cycle drags, and the dashboard drives it as a two-stage modal.

GL's eSIM LPA daemon is now controllable: `red-merle-ctl esim status|on|off|sync`, a matching libexec action, a Controls row in the dashboard, and a `disable_esim_lpa` UCI option re-applied at boot (the daemon is firmware-owned, so an upgrade re-enables it). Motivation: on this hardware the eSIM page is hidden because `/usr/share/oui/menu.d/esim.json` requires a `hardware: esim_support` capability that nothing on the firmware declares — yet the daemon still runs with `syncMode:on`, caches the IMEI on disk and embeds `esimcontrol.eiotclub.com:1887` with an `imei=%s&nonce=%s&timestamp=%s` request template. Proven off/on round trip: process gone, port 3456 closed, boot symlink removed, then restored.

Status now reports `esim_imei` and `esim_lpa` next to the modem IMEI, and both the CLI and the dashboard flag a mismatch loudly — that divergence is exactly the stale-identity leak. Control buttons finally reflect reality: `on` was always styled as the active choice regardless of the modem's answer, so the card claimed GNSS was on while the status said off.

### Dead retry branch, eiotclub port block, plain-text script output (v2.7.1)
`READ_IMEI`/`READ_IMSI` did `local imei=$(cmd)` and then tested `$?`, which is the status of `local` (always 0) rather than the command's. The whole "Failed to read IMEI. Try again?" branch was therefore unreachable and a failed read returned an empty string that callers happily used. They now test the captured value, return non-zero on failure, and — because the same helpers are called by the rpcd libexec and both web dashboards — only prompt when stdin is a TTY. A naive fix would have made the now-live `read` hang every CGI request forever; the harness gained a mute-modem test that fails if the action ever blocks instead of returning.

`SETUP_IPTABLES_BLOCKING` now also drops TCP 1887, the control channel the GL eSIM LPA daemon uses to reach `esimcontrol.eiotclub.com` with an `imei=%s&nonce=%s&timestamp=%s` payload. Profile downloads talk HTTPS/443 to the SM-DP+, so the phone-home is blocked without breaking eSIM provisioning. The `/etc/firewall.d` persistence file is also rewritten on every run instead of only when missing — the old "create if absent" guard meant a release adding a rule never reached devices that already had the file. (On GL 4.3.26 that directory does not exist at all, so persistence comes from our own init.d re-applying the rules at boot.)

Script output dropped its decorative glyphs for the `[+]` / `[-]` / `[!]` markers already used elsewhere, and the compact boot-options line reads `logs=on mac=on …` instead of check marks. The trefoil stays: it is the project mark, not decoration.

Behaviour of `/root/esim/imei`, established by experiment rather than assumption: with the file present the LPA daemon never rewrites it (a planted `000000000000000` survived a full daemon restart); with the file absent it recreates it from the live modem IMEI at mode 0600. It is a write-once store the daemon then trusts, not a refreshing cache — so a stale IMEI left there persists across reboots indefinitely.

### Toggle-path audit, footer credit links, upstream comparison rewritten (v2.8.0)
Audit of the three scripts driving the physical switch turned up two real defects. `red-merle-switch-stage2` compared `$old_imsi` against the freshly read one, but `old_imsi` is set in **stage1** — a separate process — so it was always empty: the "did you actually swap the SIM?" warning could never fire in the case it exists for, and fired spuriously whenever the IMSI was unreadable. The value now travels through `/tmp/red-merle-old-imsi`, an unreadable IMSI gets its own distinct warning, and stage1 no longer performs an unused `READ_IMEI` round trip. `${old_imei:0:15}` was a bash-only substring expansion (and a no-op on a 15-digit IMEI) surviving only thanks to busybox's bash compatibility — the same class of bug that broke CI on the libexec.

Two robustness items came with it: stage2's `until … do` retry loops were unbounded while `sim.sh` runs the script under `timeout`, so a wedged modem could get it killed *after* the IMEI change but *before* `WIPE_LOGS`, GPS hardening and DNS flush. The loops are bounded at 15 attempts and the outer timeout went from 90s to 180s (stage2 alone holds ~20s of deliberate pauses plus six modem round trips). The duplicated `/root/esim/imei` write now calls `SYNC_ESIM_IMEI`. `red-merle-mode-switch` gained the default branch its `case` lacked.

The GL panel footer credit is now clickable. Its i18n string is rendered as a text node, so markup inside it would show up literally; the injected script walks the footer for the credit text node and swaps in real anchors, cloned from the footer's own link so they inherit its scoped styling, with `rel="noopener noreferrer"`.

"Differences from blue-merle" was rewritten against the actual upstream repository rather than from memory. Upstream's last commit is June 2025; issue #1 (band fingerprinting) has been open since October 2022 and the PR proposing a fix was closed unmerged. The section now maps the upstream issues this fork answers (#1, #82, #38, #35, #22), the defects fixed (entropy, syslog leak, 14-digit validation, bash-only shell code, the eSIM identity leak), a quantified scope comparison (1,129 -> 3,291 lines, 16 -> 49 TACs, 0 -> 9 configurable behaviours), and — deliberately — the upstream issues still unaddressed here. The website's Lineage section carries the same content.

### Dashboard redesign, theme inheritance, log wiping documented (v2.9.0)
`/redmerle/` ignored the panel's theme for a precise reason: its loader read the stored theme and then skipped it when it was `default`, so none of the semantic variables were ever defined and the page fell back to the hardcoded dark values baked into its own stylesheet. It now always loads `/theme/<name>/index.css` through a stable `<link id="rm-theme">` and listens for `storage` events, so changing the palette in the panel restyles this page live in another tab. All five themes define the same 63 semantic variables, so the page could drop its palette entirely: the only hardcoded colours left are the brand trefoil and two fallbacks for `--success` / `--error`.

With colour delegated to the theme, the redesign had to earn its identity from structure. The page now opens on what the tool exists to control — the identity the network sees — as a single strip carrying the modem IMEI, the IMEI the eSIM daemon has stored, and the SIM's IMSI, with an explicit verdict between the first two: "one identity, everywhere" or "two identities on this device" plus the command that fixes it. Values are set in tabular monospace because they are numbers meant to be compared digit by digit; labels are small, spaced, uppercase and quiet. Sequence numbering appears only in the SIM swap modal, which is genuinely a two-stage procedure. Buttons carry verbs (`Set`, `Start`, `Turn off`) instead of bare states, and the highlighted toggle is the one matching the device rather than a fixed default.

The `RED MERLE` sidebar entry is a real `<a href="/redmerle/">` now instead of a `<li>` with a click handler, so middle-click and ctrl-click open it in a tab like any other link.

README log documentation replaced by something checkable: a table of exactly what is wiped, how, and what backs each target, plus the six call sites and the `wipe_logs` gate. It also states the limit honestly — `/root` sits on an overlay over UBIFS, a copy-on-write filesystem with wear levelling, so `shred` there is best-effort and the real mitigation is that red-merle never writes an identity to a persistent file to begin with. blue-merle, by comparison, ships no log-wiping code at all.

### Volatile storage, licence alignment, README brought back in line (v2.10.0)
Flash writes, not deletions, are the thing to control: `/` is an overlay over UBIFS, copy-on-write with wear levelling, so overwriting a file never overwrites the blocks that held the old content. Extending `shred` would have added wear and false comfort. Instead there are now two narrow volatile-storage switches. `volatile_history` (default on, no downside) symlinks the shell history files into tmpfs. `volatile_esim` (default **off**) mounts a tmpfs over `/root/esim`, which removes the stored identity for good — the daemon rebuilds it from the modem when the file is missing, proven by experiment — but also makes eSIM profiles volatile, hence the conservative default. A read-only overlay was considered and rejected: it breaks uci, opkg and our own toggles for very little, since almost nothing else is written at runtime.

Logs already live only in RAM (`log_file` is unset), so they die at power-off on their own; `aggressive_log_wipe` (default off, interval configurable, floor 30s) wipes them during the session too, and its cost is stated where it is offered — you also lose the ability to investigate a live compromise. All four new switches go through the existing option plumbing, so they appear in `red-merle-ctl config`, in the status JSON and in both dashboards without special-casing, with the two that trade something away carrying that caveat inline. Per-option defaults are now a function rather than a hardcoded 1, which immediately caught `disable_esim_lpa` reporting as enabled on any config file predating it.

The repository contradicted itself on its own licence: `LICENSE` is AGPL-3.0 while the Makefile and README both claimed BSD-3-Clause. Aligned on AGPL-3.0 for this fork, with `LICENSE.md` keeping SRLabs' BSD-3 notice for the inherited work, as that licence requires. No OpenWrt or GL.iNet licence file is needed — no code of theirs is redistributed; their files are patched in place on the user's own device.

README corrections: the feature list still described the four original blue-merle features and predated modes, dashboards, the control CLI and everything eSIM; the usage section offered three ways to change the IMEI when there are four; the file structure listed less than half the package. The seizure paragraph claimed no forensic trace remains, which overstates it — the current IMEI is readable from the modem and the factory one is printed on the label, so a seizure shows *that* the identity was changed. What it cannot show is the trajectory, and that distinction is now spelled out. The blue-merle `luhn.lua` row was also imprecise: the file is referenced, by two functions that nothing ever calls, with `lua` absent from the dependency list. Decorative glyphs are gone from the README and the scripts; in the trade-off lists they became `Gain:` / `Cost:`, which says more than a check mark did.

### Threat-model corrections: capability fingerprinting, hardening gradation (v2.11.0)
Two claims in the README did not survive scrutiny.

The TAC/band section implied that band-aligned TAC pools address device fingerprinting. Researching how a carrier actually learns a device's bands shows the mechanism is not inference from the band in use: the modem transmits `UECapabilityInformation` at every attach, carrying `supportedBandListEUTRA`, UE category, CA combinations, MIMO layers and feature groups. The carrier compares the fingerprint expected from the TAC against the one reported. That is deployed anti-SIM-box technology (Oh et al., NDSS 2023; US patent 12568377), not a hypothetical. **red-merle rewrites the TAC but cannot rewrite what the modem says about itself**: the reference EM060K-GL advertises 31 LTE bands against a Galaxy S21's 22, including nine the phone does not have — B14 among them, US public-safety spectrum. Band alignment defeats the coarse filter Issue #1 describes and nothing more; the README now says so, and points at band locking as the partial mitigation it is.

The mode guidance recommended hardening for "an activist under active surveillance, they already know you're a target". That reasoning is backwards for anyone who rotates identity: hardening leaves a persistent radio configuration (IMS off, LTE-only, no VoLTE, GNSS silent) that survives IMEI changes, SIM swaps and relocation, so filtering carrier records for it turns a rotation into a trail. Being known does not stop the configuration from linking future identities to the current one. The persona list is replaced by the determinants that actually decide it, and hardening is framed as a situational escalation rather than a posture.

The three things hardening adds are also not equal, which the bundle hid: LTE-only blocks a named attack (IMSI-catcher downgrade), modem-level GNSS closes the control-plane positioning path that iptables cannot reach, and IMS/VoLTE off buys almost nothing on a router with no voice path while being the rarest and most conspicuous of the three. Since `lte-only` is already independent of the mode, stealth plus `lte-only on` is now documented as the better trade for most operators. Carrier voice was also reclassified: it was never available on this device in any mode, so listing it as a cost of hardening misled — and VoIP over data is unaffected, which is what people actually care about.

### Honest summary of what the package buys (v2.11.1)
Added a "What this actually buys you" section ahead of the mode discussion, tiered by how reliable each protection is rather than by how prominent it is. The local forensic protections — no persistent identity storage, log wiping, RAM-only client database, MAC/BSSID randomization, SUPL blocking, the eSIM resync, the entropy fix — work without caveat because seizure and passive collection leave no adversary model to outsmart. The IMEI change, the headline feature, is the one carrying reservations: it defeats the coarse same-IMEI-same-device correlation that most carrier analytics actually runs, but not capability fingerprinting. The trade is now stated instead of implied — under that analysis you swap "linkable across sessions" for "flagged as anomalous each session", which is usually the better side but is not free. And the section names what nothing on the device can touch: carrier records, timing and cell correlation, and the IMSI, which links every session as long as the SIM stays the same.

## Roadmap — TAC strategy

### Verify the existing TAC mappings against a real allocation database (blocking)
Every prefix in `imei_generate.py` carries a model name in a comment, and none of
those mappings has been checked against the GSMA allocation database or a
commercial equivalent. The band-alignment argument in the README rests entirely
on them being accurate. If a prefix is unallocated, or allocated to a different
device than the comment claims, the pool is worse than useless: an unallocated
TAC is a far louder signal than a band mismatch. This has to be verified before
any further TAC work, and prefixes that cannot be confirmed should be dropped.

### Match the module, not the phone
The band list a modem reports is a property of the silicon and RF frontend, not
of the enclosure, so the only way to make `supportedBandListEUTRA` match the
claimed model exactly is to claim a device built on the same module. Quectel
lists the EM060K-GL as shipping in industrial routers, home gateways, rugged
tablets and **consumer laptops** with M.2 WWAN — and the laptop case is the
strongest cover available: same module family, and a behavioural profile that
matches a travel router closely (mobile, roams between locations, data only,
never places a voice call). Industrial and fixed-installation devices match the
radio but not the movement.

Three caveats to settle before shipping this:
- Requires verified TACs for those devices; see above. Do not invent prefixes.
- Even with an identical module, the host design's RF frontend and
  carrier-aggregation combinations can differ, so the fingerprint gets closer
  without necessarily becoming identical.
- An exact match narrows the anonymity set. If only a handful of models share
  that fingerprint, matching it perfectly places you in a small, enumerable
  crowd — which may be worse than sitting inside a large population with a minor
  inconsistency. Whether to optimise for fingerprint fidelity or for population
  size is a real design decision, not an obvious one.

### Band locking to match the claimed TAC
`AT+QNWPREFCFG="lte_band"` restricts which bands the module will use, narrowing
what it advertises. Pair it with the selected TAC so the reported set does not
exceed the claimed device's. Partial by nature — category, CA combinations and
feature groups stay module-specific — and it costs coverage, so it belongs
behind an option rather than in the default path.

### TAC pools were fabricated — replaced with verified ones (v2.12.0)
Checking the shipped TAC prefixes against a public allocation database
([github.com/MoazEb/tac-database](https://github.com/MoazEb/tac-database), ~255k
entries) found that the pools were almost entirely wrong. Of 40 prefixes, 7
matched their comment, 24 were allocated to a completely different device and 9
did not appear at all. `35332211`, commented "Galaxy S21 5G SM-G991B", is
registered to an ITEL IT5250. `35236208`, commented "Netgear Nighthawk M2", is a
ZOPO C3. `35320810`, commented "iPhone 12", is an iPad 7th gen.

This inverted the comparison the README was making. blue-merle's 16 prefixes
verify 16/16 as real and correctly attributed; they were chosen without regard to
band profile, which is the substance of upstream Issue #1, but they are genuine.
Our replacements were not, and a TAC that resolves to a basic feature phone on a
device negotiating LTE-A Cat 6 is a far louder anomaly than the band mismatch the
pools were meant to fix. The README claimed an improvement that was a regression.

Both pools were rebuilt from verified entries: 38 unique prefixes, all present in
the database and matching the model named in their comment, drawn from
high-volume devices whose band profile covers the modem's. Selection criteria are
now recorded in priority order — band coverage first, deployment volume as the
tie-breaker — and the README carries a warning to re-verify rather than inherit
the assumption, naming this regression explicitly.

Remaining gap: band coverage is established from device class (international
variants of recent flagships carry the European FDD and TDD sets) and spot
checked against published specifications, not verified per device from a spec
database. [cacombos.com](https://cacombos.com) publishes per-device band and
carrier-aggregation combinations and would allow both a systematic band check and
a first look at how close any candidate's capability fingerprint gets to the
module's.

### Native GL.iNet claim, operator-chosen TAC, hotspot-weighted pools (v2.13.0)
Three additions on top of the verified pools.

`imei native` draws from a real GL.iNet TAC (`35996594`, GL.INET 4G LTE WIRELESS). No
host-side change can alter the capability profile the modem reports, so no borrowed TAC
will ever match it exactly — the one claim that stays coherent by construction is the
product line this device belongs to. The trade is the anonymity set, which is small, so
it is a deliberate choice for situations where the device type is already known or
assumed rather than a default.

`imei_generate.py -t <8 digits>` accepts an operator-supplied TAC, validated for shape
only. Offered because there are cases where the operator knows exactly what they are
claiming; explicitly not recommended, and it prints why every time it runs.

Pool composition was rebalanced after noticing that selection is uniform, which makes
composition the actual policy: at 6 hotspots against 24 phones, four draws in five handed
out a phone. Each pool is now 42 prefixes, 18 of them portable LTE hotspots. That fixes a
behavioural mismatch no TAC choice can otherwise repair — a data-only router that never
places a voice call is unremarkable for a MiFi and conspicuous for a Galaxy. Fixed home
routers were filtered out (a desk appliance that moves between cities is its own anomaly)
along with 3G-only devices, which cannot be camping on LTE. Phones stay in the mix for
crowd size and brand diversity, since an all-Huawei pool would be a pattern in itself.
All 57 unique prefixes across the three pools verify against the allocation database.

### The native TAC is a permanent correlator (v2.13.1)
`imei native` was documented as trading capability coherence for a small anonymity set.
That undersold it. Only the serial varies between generations, so the prefix `35996594`
is present in every session the mode ever produces — an analyst filtering for that
substring reunites all of them without parsing a single capability report. It is the
same failure this README already warns about for hardening mode: an attribute that
outlives the rotation it exists to enable.

The two options do not cost the same kind of thing, and naming that settles the default.
Rotating TACs risks a **hypothetical** flag, requiring the carrier to both run capability
fingerprinting and act on the result. A fixed native TAC creates a **certain** link,
available to anyone who can match a substring. Native is now documented as earning its
place only where the device type is already known or assumed, so the link it creates
reveals nothing new.

### Choose what device the IMEI claims to be (v2.14.0)
The flat prefix lists became a single annotated pool: every entry carries brand, device type
and model alongside its verified TAC, and the modem variants it fits. Filtering is derived
from that metadata, so adding an entry makes it selectable without touching any code.

`imei_generate.py` gained `--brand`, `--type`, `--model` and `--list-pool`; `red-merle-ctl`
exposes them as `imei brand <name>`, `imei type hotspot|phone`, `imei model <text>` and
`imei pool`. An impossible combination (Apple hotspots, say) refuses and points at
`--list-pool` rather than silently widening the search and handing back something the
operator did not ask for. The dashboard carries the same choice as a dropdown next to the
IMEI button, with the consequence of each option written beside it — "portable hotspot:
closest match to this device", "phone: bigger crowd, but it never places a call", "GL.iNet:
coherent, but the prefix links every session" — because a picker that hides its trade-offs
just moves the mistake somewhere else.

Website brought level with the README: a new Identity section covers TAC verification against
the allocation database, pool composition and why it leans on hotspots, the filters, the
native claim and its cost, and what no host-side change can do about the capability report.

### Pool description in the README still described the fabricated lists (v2.14.1)
The "Two separate lists are maintained" section still enumerated the pools as they were
before verification — Netgear Nighthawk M1/M2, Huawei E5787/E5885/E5788, Galaxy A52/A33/A34,
Xiaomi 12 Pro, 24 and 25 entries. None of those prefixes survived the allocation check.
Replaced with what actually ships: one annotated pool, 42 prefixes per modem variant,
18 of them portable hotspots, and the reasoning behind that weighting.

### Regional variant lost from the pool metadata (v2.14.2)
Building the annotated pool truncated each model name at the first comma, which discarded
the designation that identifies the regional variant: `SM-G991U` (US) and `SM-G991B`
(international) both became "GALAXY S21 5G". The pool stopped being auditable and
`--model` could no longer distinguish them. Model names are re-derived from the allocation
database and now carry the designation and a US marker where applicable.

The harm this could have caused was checked rather than assumed: US Samsung variants were
suspected of lacking B20 (800 MHz, primary in much of Europe), which would have produced
exactly the coarse mismatch the pools exist to avoid. Verification shows SM-G991U does
support B20, so no shipped prefix is known to be band-incoherent. Per-device band
verification across the whole pool remains the open item.

### Band verification, iteration 1: hotspots are the unverified half (v2.15.0)
Auditing the pool device by device produced two findings, one of them uncomfortable.

Eight entries the allocation database listed only as "HUAWEI MOBILE WIFI", with no model
designation, were removed. Nothing could be verified about them — a bare "Mobile WiFi" could
as easily be a 3G-era E5330 as a current Cat6 unit, and a 3G device cannot be camping on LTE
at all.

The second finding inverts part of the earlier reasoning. Band coverage checks out for the
phones: international Samsung, Apple and Pixel variants carry the full European set including
B20, and the suspicion that US Samsung variants might lack it was checked and is false. The
Huawei hotspots are the opposite: the designations recorded in the allocation database do not
map cleanly onto published spec sheets, and Huawei MiFi regional variants differ on exactly
B20 — the E5786s-63a carries B1/3/7/8/28/40 and no B20, which is the coverage band for French
operators. So the entries chosen for their behavioural fit are the ones whose bands cannot be
confirmed, while the entries with a behavioural mismatch are the ones that verify. Both sides
of that trade are now stated where the pool is described, with `imei type phone` offered as
the verified-band option.

### The behavioural argument for hotspots does not hold (v2.15.1)
The pools were weighted toward hotspots on the grounds that a phone which never places a
voice call would look inconsistent. That reasoning fails in 2026: carrier voice is a
minority behaviour, OTT messaging replaced it for a large share of subscribers, and
data-only plans are common on phones as well — a device that never places a CS or VoLTE
call is unremarkable. This project's own documentation already says as much elsewhere,
noting that carrier voice is irrelevant for a data-only router SIM.

With that argument withdrawn and the previous iteration having shown that phones are the
entries whose band coverage actually verifies, nothing is left weighting the pool against
them. The claim is removed from the code comments, the README (three places), the website
and the dashboard's option labels, and replaced by what the composition now rests on:
verified band coverage, brand diversity, and the exclusions that still stand — fixed home
routers cannot travel, 3G-only devices cannot camp on LTE.

### Flash inventory: three artefacts nobody was cleaning (v2.15.2)
Prompted by finding a stale backup directory left on the device, an inventory of everything
red-merle causes to be written to flash turned up three problems.

`WIPE_LOGS` did `rm -f /root/.ash_history`, but volatile storage had just replaced that path
with a symlink into tmpfs. Removing a symlink removes the link, not its target, so every log
wipe silently dismantled the volatile setup and sent the next shell back to writing history
on flash. It now empties the target when the path is a symlink and only unlinks a real file.
Two features that each worked alone, quietly cancelling each other.

`/etc/config/red-merle-opkg` is parked beside the live config by opkg whenever an upgrade
finds the two differ, and belongs to no package — so `opkg remove red-merle` left it behind
as proof the package had been installed. Both postrm paths remove it now.

`/root/.wget-hsts` records which hosts wget contacted and when. Installing from the OpenWrt
feed leaves `downloads.openwrt.org` in it with a timestamp, which on a seized device says
packages were installed here, on this date. red-merle does not write it, but its install
procedure causes it, so `WIPE_LOGS` shreds it.

### LuCI entry invisible, literal newlines on the OLED, on-demand front panel (v2.16.0)
The LuCI page shipped a menu definition and an ACL, and neither took effect: LuCI serves its
menu from a cached tree and rpcd reads ACL files only at start, so a freshly installed page
stayed invisible in the Network menu and its backend calls were denied — the dashboard showed
"unknown" for every field while the GL-native page, which goes through a CGI instead of rpcd,
worked fine. Both postinst paths now drop the LuCI index cache and reload rpcd. Existing LuCI
sessions still need a re-login to pick up the ACL.

The OLED displayed a literal `\n`. `init.d` had been fixed to use printf in 2.5.0, but the
libexec's `show_message`, `CHECK_ABORT` and the interactive CLI still used `echo`, which does
not expand escapes — and the MCU renders the string as-is rather than decoding JSON escapes,
so the two characters reached the screen. All three now use `printf '%b'`, verified at byte
level: `0a` where the newline belongs, no `5c 6e` anywhere.

The screen also keeps whatever it was last sent, which made red-merle's messages look like
they surfaced at random — what was actually showing was the leftover of an earlier IMEI read.
New `oled` and `oled-clear` actions push the current identity to the front panel or wipe it,
exposed as `red-merle-ctl oled` and as two buttons in the dashboard. Nothing writes to the
screen now unless an operator asks or a swap is in progress.

### The LuCI dashboard was dead for a reason outside red-merle (v2.16.2)
Every field on the LuCI page read "unknown" while the GL-native page worked. The ACL was
granted — `session access` on `file exec` for our libexec returns true — and the backend
answered correctly when called over ubus directly. The break was in nginx: LuCI posts its
ubus calls to `/ubus`, and the stock GL configuration proxies only `/ubus/` with a trailing
slash. The exact path fell through to a 301, the redirect dropped the POST body, and every
call came back empty. Not specific to this package: any LuCI application using ubus is
affected on this firmware. An exact-match `location = /ubus` in our drop-in takes priority
over the prefix and fixes it without editing GL's file; `POST /ubus` now returns the full
status JSON.

### The OLED never displayed what the code sent (v2.16.1)
Verified against the physical panel rather than assumed, which overturned the note in the
project guide. The MCU **wraps long strings by itself**; a literal `\n` reaches the screen as
two visible characters; and a real newline makes the JSON invalid, so the message is dropped
and the panel keeps whatever it showed before. Both of the approaches in the tree were
therefore wrong — `echo` produced visible `\n`, and the `printf` "fix" from 2.5.0 made
messages vanish entirely, which means the boot summary has been invisible ever since.

Every OLED string is now a single line with no separator at all, and `show_message` folds any
newline a caller passes back to a space rather than trusting it. The boot summary reads
"RED MERLE: + Network blocked + Logs wiped ..." on one line and lets the panel wrap it.

### Iteration 3: clearing the panel, and pool counts the docs had outgrown (v2.16.3)
`oled-clear` sent a blank message, which simply replaced one custom message with another and
left the panel showing a blank rather than returning to its normal rotation. It now calls
`ubus call mcu reload`, which restarts the daemon's screen timer — effectively what the
physical button does — and falls back to the blank message if that call fails.

An implementation sweep found nothing: no bashisms, no `==` in a POSIX test, no unquoted
variable in a test, every script parses under `sh -n`, both Python files compile. Cross-checking
the 16 libexec actions against the CGI whitelist and the dashboard's calls found no action
reachable from the web that the backend does not implement, and none allowed that no longer
exists.

The README had not kept up with the previous iteration: it still advertised 42 prefixes per
modem variant and 18 hotspots, from before eight unidentifiable entries were removed. Corrected
to 34 and 10, and the comparison table to 48 unique prefixes. The website already carried the
right figure — which is the argument for the version-consistency check covering prose numbers
too, not only version strings.

### The toggle path, exercised for real for the first time (v2.17.0)
Running an actual swap surfaced what reading the code had not.

The physical switch was undocumented. Which way you slide it decides which stage runs — up
starts stage 1 and waits, down runs stage 2 and powers the device off — and sliding down
without having gone up does nothing at all. None of that appeared in the README, and the
panel said only "pull the switch" without naming a direction. Both now say UP and DOWN
explicitly, and the README carries the full sequence plus the two behaviours that look like
failures and are not: the shutdown at the end is intended, and stage 1 refuses to run twice
within 60 seconds so a bouncing switch cannot burn two IMEIs.

Three defects in the interactive CLI, in code the toggle path shares and that had never been
run end to end. The wait-for-modem loop displayed "(Ns/30s)" but had no bound, so a modem
that never answered left the counter climbing forever. It used `echo -ne`, the last bashism
in the tree — `-e` is not POSIX and this runs under busybox ash. And it printed a leftover
debug line reading "FIN". The loop is now bounded at the 30 seconds it advertises, uses
printf, and says whether the modem came back or not. The `CFUN=0`, `CFUN=4` and `QPOWD`
retry loops in the same file were also unbounded — they had been fixed in the toggle and web
paths but not here, which is exactly the path an operator uses first.

Running the flow without a SIM inserted produces "IMSI unreadable" and "IMEI unchanged"
warnings: `AT+EGMR` is unreliable while the modem cycles without a card. Documented, since
it looks like a bug and is not.

### Every IMEI change was killed by a timeout that was too short (v2.18.1)
A swap run on real hardware reported "IMEI unchanged", and the first diagnosis here was
wrong: the hardcoded `/dev/ttyUSB3` was blamed, on the reasoning that the AT port is
`/dev/ttyUSB2` on this modem. Testing each port individually disproved it — **both** answer
`AT+GSN` and **both** accept `AT+EGMR` with `OK`. The inherited default was fine, which is
also why blue-merle worked on this device.

The actual cause is timing. Modem detection alone takes ~6s, the write and its read-back
~6s more, and the modem is slower right after a `CFUN` cycle — while every caller ran the
generator under `timeout 15` (the toggle stages and the dashboard button) or `timeout 20`
(the web swap). The script was being killed mid-write. All five call sites now allow 60s.

The port-detection fix shipped for the wrong reason made this measurably worse: probing four
ports up front added ~4s to a script already at the edge of its timeout. It is kept, because
falling back to another port if the default goes silent is genuinely more robust than a
hardcoded constant, but it now tries the default first and only probes when that is silent —
about a second, instead of four.

Worth recording as a method note: the wrong diagnosis was plausible, internally consistent,
and would have survived code review. What killed it was testing each port separately instead
of trusting the first explanation that fit.


### Holding the serial port exclusively killed GL's AT broker (v2.18.2)
Changing the IMEI left `gl_modem` hanging forever: `red-merle-ctl status`, both dashboards
and the boot sequence all stopped seeing the modem, while a direct serial read worked fine.
`/usr/bin/modem_AT` owns the port and everything on the device goes through it; opening the
port with `exclusive=True` to write the IMEI knocks it over, and it does not come back on its
own. The generator now relaunches it with its original arguments after a successful write.

Verified end to end on hardware rather than argued for: IMEI 863542075580081 to
359557198511871 in 14s, `gl_modem` answering immediately afterwards, full status intact.
Two numbers worth keeping: 14s of runtime against the 15s timeout every caller used to
impose, and the fact that the failure only appears when the port is contended — which is why
no stubbed test could have caught it.

### Band verification completed: unverifiable entries removed (v2.19.0)
The per-device band check, outstanding since the pools were rebuilt, is done. The pool is
grouped into 19 model families; the phones verify — international Samsung, Apple and Pixel
variants carry the full European set including B20, and the earlier suspicion about US
Samsung variants was checked and is false. The ten Huawei hotspot entries do not: the
designations the allocation database records cannot be matched to published specifications,
and the variants differ on precisely B20, the 800 MHz coverage band for French operators.
One published figure for an E5786 variant lists B1/3/5/8/34/38/39/40/41 with no B20 at all.

They were removed rather than kept behind a caveat. A TAC whose model may not support the
band the modem is camping on produces exactly the mismatch the pools exist to prevent, so an
unverifiable entry is worse than a smaller pool — the same reasoning already applied to the
eight entries with no model name. What is left is 24 prefixes per modem variant, 39 unique,
every one checked twice: the TAC against the allocation database, the model's bands against
published specifications.

Removing a whole device class had consequences worth handling rather than leaving to break:
`--type hotspot` now matches nothing and says so with a non-zero exit, and the dashboard
builds its class list from what the pool actually contains instead of offering a hardcoded
option that would match nothing. The behavioural argument that once justified weighting
toward hotspots had already been withdrawn, so nothing is lost by their absence.

### Prose figures now checked against the code (v2.19.1)
The README quoted pool sizes that had been correct at some point and were not any more —
twice, in consecutive iterations, because removing entries updates the code and leaves the
text behind. `tests/pool-stats.py` derives the real numbers from `TAC_POOL` and
`check-version.sh` compares them against what the README and the website claim, alongside the
version strings it already guarded. Proven to work by introducing a deliberate drift (24 to
42), watching it fail with a non-zero exit, and reverting.

The LuCI dashboard was chased to the end of what can be verified from the device. Every layer
checks out: the shipped JS is byte-identical to the source and served with a 200, `fs.exec`
exists in this LuCI build and the view calls it correctly, the ACL grants `file exec` on the
libexec (`session access` returns true), and a full browser-equivalent flow — form login,
session cookie, `POST /ubus/` — returns the complete status JSON with real values. Nothing
server-side is broken, so a page still showing "unknown" is carrying stale client state.
Recorded rather than "fixed" again: three previous explanations for this were published
before being tested and all three were wrong.
