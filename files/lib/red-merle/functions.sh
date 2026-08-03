#!/usr/bin/env ash

# This script provides helper functions for red-merle


UNICAST_MAC_GEN () {
    loc_mac_numgen=`python3 -c "import random; print(f'{random.randint(0,2**48) & 0b111111101111111111111111111111111111111111111111:0x}'.zfill(12))"`
    loc_mac_formatted=$(echo "$loc_mac_numgen" | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/')
    echo "$loc_mac_formatted"
}

# randomize BSSID
RESET_BSSIDS () {
    [ "$(GET_CONFIG_OPTION randomize_bssid 1)" = "1" ] || return 0
    uci set wireless.@wifi-iface[1].macaddr=`UNICAST_MAC_GEN`
    uci set wireless.@wifi-iface[0].macaddr=`UNICAST_MAC_GEN`
    uci commit wireless
    # you need to reset wifi for changes to apply, i.e. executing "wifi"
}


RANDOMIZE_MACADDR () {
    [ "$(GET_CONFIG_OPTION randomize_mac 1)" = "1" ] || return 0
    # This changes the MAC address clients see when connecting to the WiFi spawned by the device.
    # You can check with "arp -a" that your endpoint, e.g. your laptop, sees a different MAC after a reboot of the Mudi.
    uci set network.@device[1].macaddr=`UNICAST_MAC_GEN`
    # Here we change the MAC address the upstream wifi sees
    uci set glconfig.general.macclone_addr=`UNICAST_MAC_GEN`
    uci commit network
    # You need to restart the network, i.e. /etc/init.d/network restart
}

READ_ICCID() {
    gl_modem AT AT+CCID
}

# ── GL eSIM LPA daemon ────────────────────────────────────────────────
# It caches the IMEI it last saw in /root/esim/imei and keeps a log next to
# it, both across reboots. Left alone, that file preserves the previous
# identity while the modem answers with the current one.
ESIM_DIR="/root/esim"

ESIM_CACHED_IMEI () {
    [ -f "$ESIM_DIR/imei" ] || return 0
    tr -d '\r\n' < "$ESIM_DIR/imei"
}

ESIM_LPA_STATE () {
    # bracket trick: never let the grep match its own command line
    if ps w 2>/dev/null | grep -q "[l]pa_mips"; then
        echo running
    else
        echo stopped
    fi
}

SYNC_ESIM_IMEI () {
    [ -n "$1" ] || return 1
    [ -d "$ESIM_DIR" ] || return 0
    printf '%s\n' "$1" > "$ESIM_DIR/imei" || return 1
    chmod 600 "$ESIM_DIR/imei" 2>/dev/null
    [ -f "$ESIM_DIR/log.txt" ] && shred -u "$ESIM_DIR/log.txt" 2>/dev/null
    return 0
}

# ── volatile storage ──────────────────────────────────────────────────
# / is an overlay over UBIFS: copy-on-write with wear levelling, so
# overwriting a file there does not overwrite the blocks that held the old
# content. shred is best-effort at best. Not writing to flash in the first
# place is the only thing that actually works, which is what this does.
#
# Deliberately narrow. Making /etc/config volatile would lose every setting
# at reboot, and a read-only overlay would break uci, opkg and our own
# toggles — neither is worth it when almost nothing else is written at runtime.
APPLY_VOLATILE_STORAGE () {
    # Shell history: a symlink is enough and needs no mount. ash follows it.
    if [ "$(GET_CONFIG_OPTION volatile_history 1)" = "1" ]; then
        for h in /root/.ash_history /root/.bash_history; do
            if [ ! -L "$h" ]; then
                rm -f "$h"
                ln -sf "/tmp/$(basename "$h")" "$h"
            fi
        done
    fi

    # GL's eSIM daemon state. It rebuilds /root/esim/imei from the modem when
    # the file is missing, so a tmpfs here removes the stored identity for
    # good. It also makes eSIM *profiles* volatile, hence the default of 0.
    if [ "$(GET_CONFIG_OPTION volatile_esim 0)" = "1" ] && [ -d /root/esim ]; then
        if ! mount | grep -q " /root/esim "; then
            [ -f /root/esim/log.txt ] && shred -u /root/esim/log.txt 2>/dev/null
            rm -f /root/esim/imei
            mount -t tmpfs -o mode=0700,size=1m tmpfs /root/esim 2>/dev/null
        fi
    fi
    return 0
}

# Logs already live in RAM (log_file is unset), so they die at power-off on
# their own. This is for operators who do not want them readable for the whole
# session either — off by default, because losing them also means losing any
# chance of investigating a compromise while the device is still up.
START_AGGRESSIVE_LOG_WIPE () {
    [ "$(GET_CONFIG_OPTION aggressive_log_wipe 0)" = "1" ] || return 0
    local interval=$(GET_CONFIG_OPTION log_wipe_interval 300)
    case "$interval" in
        ''|*[!0-9]*) interval=300 ;;
    esac
    [ "$interval" -lt 30 ] && interval=30
    (
        while :; do
            sleep "$interval"
            [ "$(GET_CONFIG_OPTION aggressive_log_wipe 0)" = "1" ] || exit 0
            WIPE_LOGS
        done
    ) >/dev/null 2>&1 &
    echo $! > /tmp/red-merle-logwipe.pid
    return 0
}

# Per-option defaults: most behaviours are on out of the box, the two that
# trade something away are not.
OPT_DEFAULT () {
    case "$1" in
        volatile_esim|aggressive_log_wipe|disable_esim_lpa) echo 0 ;;
        *) echo 1 ;;
    esac
}

# Enforce the UCI preference: the daemon is firmware-owned, so a firmware
# upgrade re-enables it. Called at boot.
APPLY_ESIM_LPA_POLICY () {
    [ "$(GET_CONFIG_OPTION disable_esim_lpa 0)" = "1" ] || return 0
    [ -x /etc/init.d/esim_lpa ] || return 0
    /etc/init.d/esim_lpa stop >/dev/null 2>&1
    /etc/init.d/esim_lpa disable >/dev/null 2>&1
    return 0
}


# `local var=$(cmd)` makes $? the status of `local` (always 0), so the retry
# branch below was unreachable: a failed read fell through with an empty value.
# Testing the captured output instead is both correct and simpler.
#
# The prompt only runs when a human can answer it. These helpers are also
# called by the rpcd libexec and both web dashboards, where a `read` would
# hang the request forever — those callers get a non-zero return instead.
READ_IMEI () {
	local imei
	while true; do
		imei=$(gl_modem AT AT+GSN | grep -w -E "[0-9]{14,15}")
		[ -n "$imei" ] && break
		[ -t 0 ] || return 1
		printf 'Failed to read IMEI. Try again? (Y/n): '
		read answer
		case $answer in
			n*|N*) exit 1 ;;
		esac
	done
	echo "$imei"
}

READ_IMSI () {
	local imsi
	while true; do
		imsi=$(gl_modem AT AT+CIMI | grep -w -E "[0-9]{6,15}")
		[ -n "$imsi" ] && break
		[ -t 0 ] || return 1
		printf 'Failed to read IMSI. Try again? (Y/n): '
		read answer
		case $answer in
			n*|N*) exit 1 ;;
		esac
	done
	echo "$imsi"
}


WIPE_LOGS () {
    [ "$(GET_CONFIG_OPTION wipe_logs 1)" = "1" ] || return 0
    # Clear syslog ring buffer (contains IMEI change entries)
    /etc/init.d/log restart 2>/dev/null
    # Clear kernel ring buffer
    dmesg -c > /dev/null 2>&1
    # Clear shell history. APPLY_VOLATILE_STORAGE may have replaced these with
    # symlinks into tmpfs; rm would delete the link and quietly send the next
    # shell back to writing on flash, so empty the target instead and only
    # remove a real file.
    for h in /root/.ash_history /root/.bash_history /tmp/.ash_history /tmp/.bash_history; do
        if [ -L "$h" ]; then
            : > "$h" 2>/dev/null
        elif [ -f "$h" ]; then
            rm -f "$h"
        fi
    done
    # Clear tmp logs
    rm -f /tmp/log/* 2>/dev/null
    # GL's eSIM LPA daemon logs to a file that survives reboots; it is written
    # while the modem still answers with the previous IMEI.
    [ -f /root/esim/log.txt ] && shred -u /root/esim/log.txt 2>/dev/null
    # wget's HSTS cache records which hosts were contacted and when. Installing
    # from the OpenWrt feed leaves downloads.openwrt.org in it with a timestamp,
    # which on a seized device says "packages were installed here, on this day".
    [ -f /root/.wget-hsts ] && shred -u /root/.wget-hsts 2>/dev/null
    return 0
}

DETECT_MODEM_TTY () {
    # Detect modem and find working TTY device (raw probe — used when a TTY
    # path is needed, e.g. sms send). Uses read -t instead of timeout+cat so
    # no process gets killed mid-probe (avoids "Terminated" console noise).
    local modem_model=""
    local modem_tty=""
    local tty line response

    for tty in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
        [ -c "$tty" ] || continue
        response=""
        if exec 9< "$tty" 2>/dev/null; then
            printf 'ATI\r\n' > "$tty" 2>/dev/null
            line=""; read -t 2 line <&9; response="$response$line "
            line=""; read -t 1 line <&9; response="$response$line "
            line=""; read -t 1 line <&9; response="$response$line"
            exec 9<&-
        fi
        if echo "$response" | grep -qE '(EC25|EP06|EM060K|EM05)'; then
            modem_model=$(echo "$response" | grep -oE '(EC25|EP06|EM060K|EM05)' | head -1)
            modem_tty="$tty"
            break
        fi
    done

    if [ -n "$modem_model" ] && [ -n "$modem_tty" ]; then
        echo "${modem_model}:${modem_tty}"
    else
        echo "UNKNOWN:/dev/ttyUSB3"  # fallback
    fi
}

DETECT_MODEM_MODEL () {
    # Reliable model detection via gl_modem (handles port locking).
    # Falls back to the raw TTY probe when gl_modem fails.
    local response=$(gl_modem AT AT+CGMM 2>/dev/null)
    local model=$(echo "$response" | grep -oE '(EC25|EP06|EG06|EM060K|EM05)' | head -1)
    if [ -z "$model" ]; then
        model=$(DETECT_MODEM_TTY | cut -d: -f1)
    fi
    echo "${model:-UNKNOWN}"
}

SETUP_IPTABLES_BLOCKING () {
    [ "$(GET_CONFIG_OPTION iptables_block 1)" = "1" ] || return 0
    # Block SUPL and OMA-DM traffic to prevent carrier tracking.
    # NOTE: blocking UDP/TCP 4500 also kills IPsec NAT-T passthrough,
    # so IPsec VPN clients behind the Mudi will not work. Deliberate
    # trade-off: carrier tracking resistance over IPsec support.
    # Rules are added idempotently (-C check first) as this function
    # runs both at boot and after every IMEI change.
    iptables -C OUTPUT -p tcp --dport 7275 -j DROP 2>/dev/null || iptables -I OUTPUT -p tcp --dport 7275 -j DROP
    iptables -C OUTPUT -p udp --dport 7275 -j DROP 2>/dev/null || iptables -I OUTPUT -p udp --dport 7275 -j DROP
    iptables -C OUTPUT -p tcp --dport 4500 -j DROP 2>/dev/null || iptables -I OUTPUT -p tcp --dport 4500 -j DROP
    iptables -C OUTPUT -p udp --dport 4500 -j DROP 2>/dev/null || iptables -I OUTPUT -p udp --dport 4500 -j DROP
    iptables -C OUTPUT -p tcp --dport 7273 -j DROP 2>/dev/null || iptables -I OUTPUT -p tcp --dport 7273 -j DROP
    # GL's eSIM LPA daemon control channel (esimcontrol.eiotclub.com:1887).
    # It posts imei/nonce/timestamp to a third party. Profile downloads talk
    # HTTPS to the SM-DP+ on 443, so blocking 1887 kills the phone-home
    # without breaking eSIM provisioning itself.
    iptables -C OUTPUT -p tcp --dport 1887 -j DROP 2>/dev/null || iptables -I OUTPUT -p tcp --dport 1887 -j DROP

    # Persist across reboots. Rewritten on every run, not written once: the
    # old "create if missing" guard meant an upgrade adding a rule never
    # reached devices that already had the file.
    if [ -d /etc/firewall.d ]; then
        cat > /etc/firewall.d/red-merle-blocking << 'EOF'
#!/bin/sh
# red-merle: Block carrier tracking ports
# NOTE: UDP/TCP 4500 blocking kills IPsec NAT-T passthrough (deliberate trade-off)
iptables -I OUTPUT -p tcp --dport 7275 -j DROP
iptables -I OUTPUT -p udp --dport 7275 -j DROP
iptables -I OUTPUT -p tcp --dport 4500 -j DROP
iptables -I OUTPUT -p udp --dport 4500 -j DROP
iptables -I OUTPUT -p tcp --dport 7273 -j DROP
# GL eSIM LPA control channel (eiotclub)
iptables -I OUTPUT -p tcp --dport 1887 -j DROP
EOF
        chmod +x /etc/firewall.d/red-merle-blocking
    fi
}

DISABLE_CARRIER_GPS () {
    local hardening_mode=$(GET_HARDENING_MODE)

    # Always apply network-level blocking (invisible to carrier)
    SETUP_IPTABLES_BLOCKING

    case "$hardening_mode" in
        "stealth")
            # STEALTH MODE: Only invisible modifications
            echo "Red-merle: Stealth mode - network blocking only" >/dev/null
            ;;
        "hardening")
            # HARDENING MODE: Full AT command suite
            DISABLE_CARRIER_GPS_ORIGINAL
            ;;
        *)
            # Default to stealth for unknown modes
            echo "Red-merle: Unknown mode $hardening_mode, defaulting to stealth" >/dev/null
            ;;
    esac
}

FLUSH_DNS () {
    # Flush DNS cache to prevent session correlation
    /etc/init.d/dnsmasq restart 2>/dev/null
}

CHECK_ABORT () {
        sim_change_switch=`cat /tmp/sim_change_switch`
        if [ "$sim_change_switch" = "off" ]; then
                printf '{"msg":"== RED-MERLE ==\nSIM change\naborted."}\n' > /dev/ttyS0
                sleep 1
                exit 1
        fi
}

GET_HARDENING_MODE () {
    # Read mode from UCI config
    local mode=$(uci get red-merle.settings.hardening_mode 2>/dev/null || echo "stealth")
    echo "$mode"
}

GET_CONFIG_OPTION () {
    # Read an option from UCI config, falling back to the given default
    local value=$(uci get red-merle.settings.$1 2>/dev/null || echo "$2")
    echo "$value"
}

# Wait for the Quectel modem to answer AT commands.
# At boot (START=10) the modem is not up yet, so AT commands would silently
# no-op. Poll bounded: 30 tries x 2s = 60s worst case.
WAIT_FOR_MODEM () {
    local tries=30
    while [ "$tries" -gt 0 ]; do
        if gl_modem AT AT 2>/dev/null | grep -q "OK"; then
            return 0
        fi
        tries=$((tries - 1))
        sleep 2
    done
    return 1
}

# Log of AT command responses, for on-device validation
AT_LOG="/tmp/red-merle-at.log"

# Send an AT command via gl_modem; returns 0 only if the modem answered OK.
# Commands and responses are logged to $AT_LOG instead of being swallowed
# by 2>/dev/null, so failures can be inspected on-device.
# An optional second argument lists an acceptable error string (e.g. CME 505
# for QGPSEND when GNSS is already off).
AT_SEND () {
    local response=$(gl_modem AT "$1" 2>&1)
    echo "$1 => $response" >> "$AT_LOG"
    echo "$response" | grep -q "OK" && return 0
    [ -n "$2" ] && echo "$response" | grep -q "$2"
}

# GPS/tracking hardening for GL-E750 v1 (EP06-E) and v2 (EM060K-GL)
# Command syntax verified against the official Quectel LTE-A(Q) Series
# GNSS Application Note V1.1 (covers EP06/EG06/EM06/EM060K-GL) and the
# EG06xK&Ex120K&EM060K Series AT Commands Manual V1.0.0.
# NOTE: "lppe" and "suplssl" QGPSCFG items do NOT exist on the LTE-A(Q)
# series (they are LTE Standard family commands, e.g. EC25/BG96) and
# would just return ERROR here. On this family LPP is controlled via
# agnssprotocol, and SUPL user-plane traffic is killed at the network
# layer by SETUP_IPTABLES_BLOCKING (port 7275).
DISABLE_CARRIER_GPS_ORIGINAL () {
    # Detect modem type (gl_modem is more reliable than raw TTY probing)
    local modem_model=$(DETECT_MODEM_MODEL)
    local failed=0

    # Common commands for both modems (all present in the GNSS App Note)
    AT_SEND 'AT+QGPSEND' 'CME ERROR: 505'      || failed=1  # Turn GNSS engine off (505 = already off)
    AT_SEND 'AT+QGPSCFG="agnssprotocol",0,0'   || failed=1  # Disable LPP + AGLONASS positioning protocols
    AT_SEND 'AT+QGPSCFG="agpsposmode",0'       || failed=1  # No A-GPS modes: standalone only
    AT_SEND 'AT+QGPSXTRA=0'                    || failed=1  # Disable XTRA assistance (phones home to Qualcomm izatcloud servers; enabled by default on EM060K)
    AT_SEND 'AT+QGPSCFG="gpsnmeatype",0'       || failed=1  # No NMEA output
    AT_SEND 'AT+QCFG="ims",0'                  || failed=1  # Disable VoLTE/IMS

    # Force LTE only, block 2G/3G downgrade (command differs per modem)
    case "$modem_model" in
        "EP06"|"EC25")
            AT_SEND 'AT+QCFG="nwscanmode",3,1' || failed=1
            ;;
        "EM060K"|"EM05")
            # EM060K manual 5.17.3: string values, not numeric
            AT_SEND 'AT+QNWPREFCFG="mode_pref",LTE' || failed=1
            ;;
        *)
            # Unknown modem: try both
            AT_SEND 'AT+QCFG="nwscanmode",3,1' || AT_SEND 'AT+QNWPREFCFG="mode_pref",LTE' || failed=1
            ;;
    esac

    # SUPL disable: QCFG="SUPL" only exists on the LTE Standard family
    # (EC25). On LTE-A(Q) modems SUPL has no off-switch AT command —
    # the iptables block on port 7275 is the effective control.
    if [ "$modem_model" = "EC25" ]; then
        AT_SEND 'AT+QCFG="SUPL",0' || failed=1
    fi

    return $failed
}

# Revert the persistent modem settings applied by DISABLE_CARRIER_GPS_ORIGINAL.
# nwscanmode/mode_pref/ims are stored in the modem's NV memory, so they
# survive reboots — switching back to stealth mode MUST restore them
# explicitly, otherwise the modem stays LTE-only with IMS off forever.
# GNSS-only parameters (agnssprotocol, agpsposmode, nmeatype, suplver) are
# left hardened on purpose: they affect only the modem's own positioning
# engine, never connectivity, SMS or calls.
REVERT_CARRIER_HARDENING () {
    local modem_model=$(DETECT_MODEM_MODEL)
    local failed=0

    # Re-enable all radio access technologies (per modem family)
    case "$modem_model" in
        "EP06"|"EC25")
            AT_SEND 'AT+QCFG="nwscanmode",0,1' || failed=1  # auto 2G/3G/4G, save to NV
            ;;
        "EM060K"|"EM05")
            AT_SEND 'AT+QNWPREFCFG="mode_pref",AUTO' || failed=1
            ;;
        *)
            AT_SEND 'AT+QCFG="nwscanmode",0,1' || AT_SEND 'AT+QNWPREFCFG="mode_pref",AUTO' || failed=1
            ;;
    esac

    AT_SEND 'AT+QCFG="ims",1' || failed=1   # Re-enable IMS/VoLTE (SMS-over-IP path)

    # XTRA default differs per family (GNSS App Note 1.4):
    # disabled by default on EP06, enabled by default on EM060K
    case "$modem_model" in
        "EM060K"|"EM05")
            AT_SEND 'AT+QGPSXTRA=1' || failed=1
            ;;
    esac

    return $failed
}
