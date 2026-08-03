#!/bin/bash
#
# run-dashboard-tests.sh - local harness for the red-merle LuCI dashboard backend.
#
# Stubs gl_modem / uci / iptables, runs the JSON actions of
# files/usr/libexec/red-merle against fake modem data, and proves the
# emitted JSON parses and contains every required key.
#
# Usage: tests/run-dashboard-tests.sh   (run from anywhere; cleans up after itself)

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$ROOT/tests/.sandbox"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/bin" "$SANDBOX/uci"
export SANDBOX

trap 'rm -rf "$SANDBOX"' EXIT

FAILURES=0

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

# ── fake AT log (functions.sh points AT_LOG at /tmp; redirect to sandbox) ──

sed "s|AT_LOG=\"/tmp/red-merle-at.log\"|AT_LOG=\"$SANDBOX/red-merle-at.log\"|" \
    "$ROOT/files/lib/red-merle/functions.sh" > "$SANDBOX/functions.sh"

# ── libexec under test, sourcing the sandboxed functions.sh ──

sed "s|^\. /lib/red-merle/functions\.sh$|. $SANDBOX/functions.sh|" \
    "$ROOT/files/usr/libexec/red-merle" > "$SANDBOX/red-merle"
chmod +x "$SANDBOX/red-merle"

# ── stub: gl_modem ──
# Answers the query commands with canned EM060K responses; everything else
# (AT_SEND writes) answers OK. The CGMR reply deliberately contains a
# double quote and a backslash to prove JSON sanitization.

cat > "$SANDBOX/bin/gl_modem" << 'EOF'
#!/bin/bash
# args: gl_modem AT "<command>"
cmd="$2"
case "$cmd" in
    AT+CGMM)
        printf 'EM060K-GL\n\nOK\n' ;;
    AT+CGMR)
        printf 'EM060KGLAAR03A05"M4G\\test\n\nOK\n' ;;
    AT+GSN)
        printf '869523051234567\n\nOK\n' ;;
    AT+CIMI)
        printf '262011234567890\n\nOK\n' ;;
    AT+CNUM)
        printf '+CNUM: ,"+4915112345678",145\n\nOK\n' ;;
    "AT+CPIN?")
        printf '+CPIN: READY\n\nOK\n' ;;
    "AT+CEREG?")
        printf '+CEREG: 0,1\n\nOK\n' ;;
    AT+CSQ)
        printf '+CSQ: 23,99\n\nOK\n' ;;
    AT+QNWINFO)
        printf '+QNWINFO: "FDD LTE","26201","LTE BAND 20",6300\n\nOK\n' ;;
    "AT+QGPS?")
        printf '+QGPS: 1\n\nOK\n' ;;
    'AT+QNWPREFCFG="mode_pref"')
        printf '+QNWPREFCFG: "mode_pref",LTE\n\nOK\n' ;;
    'AT+QCFG="nwscanmode"')
        printf '+QCFG: "nwscanmode",0\n\nOK\n' ;;
    *)
        printf 'OK\n' ;;
esac
exit 0
EOF

# ── stub: uci ──
# Key/value store in $SANDBOX/uci, one file per key.

cat > "$SANDBOX/bin/uci" << 'EOF'
#!/bin/bash
store="$SANDBOX/uci"
case "$1" in
    get)
        key="${2#red-merle.settings.}"
        [ "$key" = "$2" ] && exit 1
        [ -f "$store/$key" ] || exit 1
        cat "$store/$key"
        ;;
    set)
        expr="$2"
        key="${expr#red-merle.settings.}"
        key="${key%%=*}"
        val="${expr#*=}"
        printf '%s' "$val" > "$store/$key"
        ;;
    commit)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
exit 0
EOF

# ── stub: iptables ──
# Only -C checks matter; SUPL rule state toggled via $SANDBOX/supl-active.

cat > "$SANDBOX/bin/iptables" << 'EOF'
#!/bin/bash
if [ "$1" = "-C" ]; then
    case "$*" in
        *"--dport 7275"*)
            [ -f "$SANDBOX/supl-active" ] && exit 0 || exit 1 ;;
        *)
            exit 1 ;;
    esac
fi
# -I / -A inserts: pretend success
exit 0
EOF

chmod +x "$SANDBOX/bin/"*

run() {
    PATH="$SANDBOX/bin:/usr/bin:/bin" sh "$SANDBOX/red-merle" "$@" 2>"$SANDBOX/stderr"
}

json_check() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
name, path = sys.argv[1], sys.argv[2]
raw = open(path).read()
try:
    data = json.loads(raw)
except Exception as e:
    print("FAIL: %s: invalid JSON: %s (raw: %r)" % (name, e, raw[:200]))
    sys.exit(1)
print("OK: %s parses as JSON" % name)
if name == "status":
    required = ["modem_model", "modem_fw", "imei", "imsi", "number", "sim",
                "registration", "signal", "network", "hardening_mode",
                "lte_only", "gnss", "supl_block", "opts"]
    missing = [k for k in required if k not in data]
    if missing:
        print("FAIL: status missing keys: %s" % missing)
        sys.exit(1)
    opts_required = ["wipe_logs", "randomize_mac", "randomize_bssid",
                     "iptables_block", "gps_hardening"]
    missing = [k for k in opts_required if k not in data["opts"]]
    if missing:
        print("FAIL: status.opts missing keys: %s" % missing)
        sys.exit(1)
    for k in opts_required:
        if data["opts"][k] not in (0, 1):
            print("FAIL: status.opts.%s not 0/1: %r" % (k, data["opts"][k]))
            sys.exit(1)
    print(json.dumps(data, indent=2))
PYEOF
}

echo "== syntax check =="
if bash -n "$ROOT/files/usr/libexec/red-merle"; then
    echo "OK: bash -n"
else
    fail "bash -n failed"
fi

echo "== status (defaults, SUPL active) =="
echo 1 > "$SANDBOX/uci/wipe_logs"
echo 0 > "$SANDBOX/uci/randomize_mac"
touch "$SANDBOX/supl-active"
run status > "$SANDBOX/out-status"
json_check status "$SANDBOX/out-status" || FAILURES=$((FAILURES + 1))

python3 - "$SANDBOX/out-status" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
checks = [
    (d["modem_model"], "EM060K"),
    (d["imei"], "869523051234567"),
    (d["imsi"], "262011234567890"),
    (d["number"], "+4915112345678"),
    (d["sim"], "READY"),
    (d["signal"], "23,99"),
    (d["lte_only"], "on"),
    (d["gnss"], "on"),
    (d["supl_block"], "active"),
    (d["opts"]["wipe_logs"], 1),
    (d["opts"]["randomize_mac"], 0),
]
for got, want in checks:
    if got != want:
        print("FAIL: expected %r, got %r" % (want, got))
        sys.exit(1)
if '"' in d["modem_fw"] or "\\" in d["modem_fw"]:
    print("FAIL: modem_fw not sanitized: %r" % d["modem_fw"])
    sys.exit(1)
print("OK: status values + sanitization (fw=%r)" % d["modem_fw"])
PYEOF

echo "== status (SUPL inactive) =="
rm -f "$SANDBOX/supl-active"
run status > "$SANDBOX/out-status2"
python3 - "$SANDBOX/out-status2" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d["supl_block"] == "inactive", d["supl_block"]
print("OK: supl_block=inactive detected")
PYEOF

echo "== set-option =="
run set-option wipe_logs 0 > "$SANDBOX/out-so1"
json_check set-option "$SANDBOX/out-so1" || FAILURES=$((FAILURES + 1))
python3 - "$SANDBOX/out-so1" "$SANDBOX/uci/wipe_logs" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {"ok": True}, d
assert open(sys.argv[2]).read() == "0"
print("OK: set-option applied (wipe_logs=0)")
PYEOF
run set-option wipe_logs 0 > "$SANDBOX/out-so2"   # idempotent second call
python3 - "$SANDBOX/out-so2" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
assert json.load(open(sys.argv[1])) == {"ok": True}
print("OK: set-option idempotent")
PYEOF
run set-option bogus 1 > "$SANDBOX/out-so3"
python3 - "$SANDBOX/out-so3" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is False and "error" in d, d
print("OK: set-option rejects unknown option: %s" % d["error"])
PYEOF
run set-option wipe_logs 7 > "$SANDBOX/out-so4"
python3 - "$SANDBOX/out-so4" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is False and "error" in d, d
print("OK: set-option rejects bad value: %s" % d["error"])
PYEOF

echo "== lte-only / gps / hardening =="
for args in "lte-only on" "lte-only off" "gps on" "gps off" "hardening on" "hardening off"; do
    run $args > "$SANDBOX/out-toggle"
    json_check "$args" "$SANDBOX/out-toggle" || FAILURES=$((FAILURES + 1))
done
python3 - "$SANDBOX/uci/hardening_mode" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import sys
mode = open(sys.argv[1]).read()
assert mode == "stealth", mode
print("OK: hardening on->off round trip ends in stealth mode")
PYEOF

echo "== at-log (present, >40 lines, quotes/backslashes) =="
rm -f "$SANDBOX/red-merle-at.log"
for i in $(seq 1 45); do
    printf 'AT+QCFG="nwscanmode",%s,1 => \\r\\nOK line %s\n' "$i" "$i" >> "$SANDBOX/red-merle-at.log"
done
run at-log > "$SANDBOX/out-log1"
json_check at-log "$SANDBOX/out-log1" || FAILURES=$((FAILURES + 1))
python3 - "$SANDBOX/out-log1" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
lines = d["lines"]
assert len(lines) == 40, len(lines)
assert "line 45" in lines[-1] and "line 6" in lines[0]
assert 'AT+QCFG="nwscanmode"' in lines[0]
print("OK: at-log returns last 40 lines, quoting intact")
PYEOF

echo "== at-log (absent) =="
rm -f "$SANDBOX/red-merle-at.log"
run at-log > "$SANDBOX/out-log2"
python3 - "$SANDBOX/out-log2" << 'PYEOF' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {"lines": []}, d
print("OK: at-log absent file -> {\"lines\":[]}")
PYEOF

echo "== non-interactive read must fail fast, never prompt =="

# A modem that answers nothing used to leave READ_IMEI waiting on `read`,
# which would hang a CGI request forever. Swap in a mute stub and make
# sure the action returns instead of blocking.
cp "$SANDBOX/bin/gl_modem" "$SANDBOX/gl_modem.real"
printf '#!/bin/bash\nexit 0\n' > "$SANDBOX/bin/gl_modem"
chmod +x "$SANDBOX/bin/gl_modem"
if timeout 10 env PATH="$SANDBOX/bin:/usr/bin:/bin" sh "$SANDBOX/red-merle" read-imei \
        > "$SANDBOX/out-mute" 2>/dev/null; then
    echo "OK: read-imei returned with a mute modem"
else
    rc=$?
    if [ "$rc" = "124" ]; then
        fail "read-imei hung on a mute modem (waiting for input)"
    else
        echo "OK: read-imei failed fast with a mute modem (rc=$rc)"
    fi
fi
cp "$SANDBOX/gl_modem.real" "$SANDBOX/bin/gl_modem"

echo "== new dispatch branches (esim / sim-swap) =="

run esim bogus > "$SANDBOX/out-esim1"
python3 - "$SANDBOX/out-esim1" << 'PYCHK' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is False and "usage" in d["error"], d
print("OK: esim rejects an unknown sub-command as JSON")
PYCHK

run sim-swap bogus > "$SANDBOX/out-swap1"
python3 - "$SANDBOX/out-swap1" << 'PYCHK' || FAILURES=$((FAILURES + 1))
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is False and "usage" in d["error"], d
print("OK: sim-swap rejects an unknown stage as JSON")
PYCHK

echo "== legacy actions unchanged =="
run read-imei > "$SANDBOX/out-imei"
IMEI=$(cat "$SANDBOX/out-imei")
if [ "$IMEI" = "869523051234567" ]; then
    echo "OK: read-imei still outputs bare IMEI"
else
    fail "read-imei output changed: '$IMEI'"
fi
run read-imsi > "$SANDBOX/out-imsi"
IMSI=$(cat "$SANDBOX/out-imsi")
if [ "$IMSI" = "262011234567890" ]; then
    echo "OK: read-imsi still outputs bare IMSI"
else
    fail "read-imsi output changed: '$IMSI'"
fi
run bogus-action > "$SANDBOX/out-unknown"
if [ "$(cat "$SANDBOX/out-unknown")" = "0" ]; then
    echo "OK: unknown action still outputs 0"
else
    fail "unknown action output changed"
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "$FAILURES TEST(S) FAILED"
    exit 1
fi
