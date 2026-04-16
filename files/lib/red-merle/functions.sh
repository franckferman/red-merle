#!/usr/bin/env ash

# This script provides helper functions for red-merle


UNICAST_MAC_GEN () {
    loc_mac_numgen=`python3 -c "import random; print(f'{random.randint(0,2**48) & 0b111111101111111111111111111111111111111111111111:0x}'.zfill(12))"`
    loc_mac_formatted=$(echo "$loc_mac_numgen" | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/')
    echo "$loc_mac_formatted"
}

# randomize BSSID
RESET_BSSIDS () {
    uci set wireless.@wifi-iface[1].macaddr=`UNICAST_MAC_GEN`
    uci set wireless.@wifi-iface[0].macaddr=`UNICAST_MAC_GEN`
    uci commit wireless
    # you need to reset wifi for changes to apply, i.e. executing "wifi"
}


RANDOMIZE_MACADDR () {
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


READ_IMEI () {
	local answer=1
	while [[ "$answer" -eq 1 ]]; do
	        local imei=$(gl_modem AT AT+GSN | grep -w -E "[0-9]{14,15}")
	        if [[ $? -eq 1 ]]; then
                	echo -n "Failed to read IMEI. Try again? (Y/n): "
	                read answer
	                case $answer in
	                        n*) answer=0;;
	                        N*) answer=0;;
	                        *) answer=1;;
	                esac
	                if [[ $answer -eq 0 ]]; then
	                        exit 1
	                fi
	        else
	                answer=0
	        fi
	done
	echo $imei
}

READ_IMSI () {
	local answer=1
	while [[ "$answer" -eq 1 ]]; do
	        local imsi=$(gl_modem AT AT+CIMI | grep -w -E "[0-9]{6,15}")
	        if [[ $? -eq 1 ]]; then
                	echo -n "Failed to read IMSI. Try again? (Y/n): "
	                read answer
	                case $answer in
	                        n*) answer=0;;
	                        N*) answer=0;;
	                        *) answer=1;;
	                esac
	                if [[ $answer -eq 0 ]]; then
	                        exit 1
	                fi
	        else
	                answer=0
	        fi
	done
	echo $imsi
}


GENERATE_IMEI() {
    local seed=$(head -100 /dev/urandom | tr -dc "0123456789" | head -c10)
    local imei=$(lua /lib/red-merle/luhn.lua $seed)
    echo -n $imei
}

SET_IMEI() {
    local imei="$1"

    if [[ ${#imei} -eq 14 ]]; then
        gl_modem AT AT+EGMR=1,7,${imei}
    else
        echo "IMEI is ${#imei} not 14 characters long"
    fi
}

WIPE_LOGS () {
    # Clear syslog ring buffer (contains IMEI change entries)
    /etc/init.d/log restart 2>/dev/null
    # Clear kernel ring buffer
    dmesg -c > /dev/null 2>&1
    # Clear shell history
    rm -f /root/.ash_history /root/.bash_history /tmp/.ash_history
    # Clear tmp logs
    rm -f /tmp/log/* 2>/dev/null
}

DETECT_MODEM_TTY () {
    # Detect modem and find working TTY device
    local modem_model=""
    local modem_tty=""

    for tty in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
        if [ -c "$tty" ]; then
            local response=$(timeout 3 printf 'ATI\r\n' > "$tty" 2>/dev/null && timeout 3 cat < "$tty" 2>/dev/null | head -5)
            if echo "$response" | grep -qE '(EC25|EP06)'; then
                modem_model=$(echo "$response" | grep -oE '(EC25|EP06)' | head -1)
                modem_tty="$tty"
                break
            fi
        fi
    done

    if [ -n "$modem_model" ] && [ -n "$modem_tty" ]; then
        echo "${modem_model}:${modem_tty}"
    else
        echo "UNKNOWN:/dev/ttyUSB3"  # fallback
    fi
}

SETUP_IPTABLES_BLOCKING () {
    # Block SUPL and OMA-DM traffic to prevent carrier tracking
    iptables -I OUTPUT -p tcp --dport 7275 -j DROP 2>/dev/null
    iptables -I OUTPUT -p udp --dport 7275 -j DROP 2>/dev/null
    iptables -I OUTPUT -p tcp --dport 4500 -j DROP 2>/dev/null
    iptables -I OUTPUT -p udp --dport 4500 -j DROP 2>/dev/null
    iptables -I OUTPUT -p tcp --dport 7273 -j DROP 2>/dev/null

    # Make rules persistent across reboots
    if [ -d /etc/firewall.d ]; then
        cat > /etc/firewall.d/red-merle-blocking << 'EOF'
#!/bin/sh
# red-merle: Block carrier tracking ports
iptables -I OUTPUT -p tcp --dport 7275 -j DROP
iptables -I OUTPUT -p udp --dport 7275 -j DROP
iptables -I OUTPUT -p tcp --dport 4500 -j DROP
iptables -I OUTPUT -p udp --dport 4500 -j DROP
iptables -I OUTPUT -p tcp --dport 7273 -j DROP
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
    killall dnsmasq 2>/dev/null
    /etc/init.d/dnsmasq restart 2>/dev/null
}

DETECT_MODEM () {
    # Returns modem model identifier
    local model=$(gl_modem AT AT+CGMM 2>/dev/null | grep -oE '(EP06|EM05|EM060K|EC25|EG06)')
    echo "${model:-UNKNOWN}"
}

CHECK_ABORT () {
        sim_change_switch=`cat /tmp/sim_change_switch`
        if [[ "$sim_change_switch" = "off" ]]; then
                echo '{ "msg": "SIM change      aborted." }' > /dev/ttyS0
                sleep 1
                exit 1
        fi
}

GET_HARDENING_MODE () {
    # Read mode from UCI config
    local mode=$(uci get red-merle.settings.hardening_mode 2>/dev/null || echo "stealth")
    echo "$mode"
}

# Rename original function
DISABLE_CARRIER_GPS_ORIGINAL () {
    # Enhanced GPS/tracking hardening for GL-E750 v1 (EC25) and v2 (EP06-E)

    # Detect modem type and TTY
    local modem_info=$(DETECT_MODEM_TTY)
    local modem_model=$(echo "$modem_info" | cut -d: -f1)
    local modem_tty=$(echo "$modem_info" | cut -d: -f2)

    # Common commands for both modems
    gl_modem AT 'AT+QGPS=0' 2>/dev/null                    # Disable GPS engine
    gl_modem AT 'AT+QGPSEND' 2>/dev/null                   # End GPS session
    gl_modem AT 'AT+QGPSCFG="lppe",0,0' 2>/dev/null       # Disable LPP positioning
    gl_modem AT 'AT+QGPSCFG="agpsposmode",1' 2>/dev/null  # Force standalone GPS only
    gl_modem AT 'AT+QCFG="ims",0' 2>/dev/null             # Disable VoLTE/IMS
    gl_modem AT 'AT+QNWPREFMDE=38' 2>/dev/null            # Force LTE only, block 2G/3G downgrade

    # Modem-specific SUPL configuration
    case "$modem_model" in
        "EC25")
            gl_modem AT 'AT+QCFG="SUPL",0' 2>/dev/null     # EC25: Disable SUPL via QCFG
            ;;
        "EP06")
            gl_modem AT 'AT+QGPSCFG="suplssl",0' 2>/dev/null  # EP06: Disable SUPL SSL
            ;;
        *)
            # Try both commands for unknown modems
            gl_modem AT 'AT+QCFG="SUPL",0' 2>/dev/null
            gl_modem AT 'AT+QGPSCFG="suplssl",0' 2>/dev/null
            ;;
    esac

    # Legacy commands for backward compatibility
    gl_modem AT 'AT+QGPSCFG="agpsposmode",0' 2>/dev/null
    gl_modem AT 'AT+QGPSCFG="gpsnmeatype",0' 2>/dev/null
    gl_modem AT 'AT+QGPSCFG="suplver",0' 2>/dev/null
}
