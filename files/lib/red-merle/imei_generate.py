#!/usr/bin/env python3
import random
import string
import argparse
import os
import serial
import re
import subprocess
import sys
from functools import reduce
from enum import Enum


class Modes(Enum):
    DETERMINISTIC = 1
    RANDOM = 2
    STATIC = 3


ap = argparse.ArgumentParser()
ap.add_argument("-v", "--verbose", help="Enables verbose output",
                action="store_true")
ap.add_argument("-g", "--generate-only", help="Only generates an IMEI rather than setting it",
                   action="store_true")
modes = ap.add_mutually_exclusive_group()
modes.add_argument("-d", "--deterministic", help="Switches IMEI generation to deterministic mode", action="store_true")
modes.add_argument("-s", "--static", help="Sets user-defined IMEI",
                   action="store")
modes.add_argument("-r", "--random", help="Sets random IMEI",
                   action="store_true")
ap.add_argument("-t", "--tac", action="store",
                help="Use this exact 8-digit TAC instead of a pool. NOT "
                     "RECOMMENDED: nothing checks that the device it belongs "
                     "to can produce the radio capabilities this modem "
                     "reports, and an unallocated TAC is worse than no "
                     "spoofing at all. For operators who know what they are "
                     "claiming and why.")
ap.add_argument("--brand", action="store",
                help="Only claim devices of this brand (apple, samsung, huawei, "
                     "google, xiaomi). Combine with --type/--model.")
ap.add_argument("--type", dest="dtype", action="store",
                help="Only claim this device class: hotspot or phone. Phone "
                     "entries are the ones whose band coverage is verified.")
ap.add_argument("--model", action="store",
                help="Only claim models whose name contains this text, e.g. "
                     "\"iphone 15\" or \"mobile wifi\".")
ap.add_argument("--list-pool", action="store_true",
                help="Print the verified TAC pool and exit.")
ap.add_argument("-n", "--native", action="store_true",
                help="Draw the TAC from the GL.iNet pool: claim to be what this "
                     "device is, so the radio capability profile stays coherent")

# Example IMEI: 490154203237518
imei_length = 14  # without validation digit

# TAC prefixes. Every entry below was verified against a public Type Allocation
# Code database (github.com/MoazEb/tac-database, ~255k allocations) — the model
# named in each comment is what that TAC is really registered to.
#
# This matters more than band alignment: an unallocated or misattributed TAC is
# a far louder signal than a band mismatch. A carrier resolving the TAC gets
# "no such device" or a model whose capabilities cannot possibly match what the
# modem reports. Never add a prefix here without checking it first.
#
# Selection criteria, in order:
#   1. Band coverage. The claimed model's LTE band profile must be a superset of
#      the bands the modem actually uses, or the cheapest possible carrier query
#      ("does this model even support the band it is camping on?") flags it.
#      VERIFIED for the phones: international Samsung/Apple/Pixel variants carry
#      the full European set including B20 (800 MHz, primary for French
#      operators). NOT verified for the Huawei hotspots: the designations the
#      allocation database records do not map cleanly onto published spec
#      sheets, and Huawei MiFi regional variants differ on exactly that band —
#      the E5786s-63a, for instance, has B1/3/7/8/28/40 and no B20. Treat the
#      Huawei hotspot entries were removed for that reason: their published
#      specifications could not be matched to the designations the allocation
#      database records, and the variants differ on B20 — the 800 MHz coverage
#      band for French operators. A TAC whose model may not support the band the
#      modem is camping on is the exact mismatch these pools exist to avoid, so
#      an unverifiable entry is worse than a smaller pool. Re-add them only with
#      per-model band data in hand.
#
#      Hotspots were once weighted higher on the argument that a phone which
#      never places a voice call would stand out. That does not hold in 2026:
#      carrier voice is a minority behaviour, OTT messaging replaced it, and
#      data-only plans are common on phones too. With the behavioural argument
#      gone and the band evidence favouring phones, there is no reason left to
#      weight against them.
#   2. Deployment volume, as a tie-breaker. The population you disappear into is
#      part of the protection, so a device sold in the tens of millions beats an
#      equally plausible one sold in thousands.
#
# Band coverage here is established from device class — international/global
# model variants of recent flagships and upper-midrange phones all carry the
# European B1/B3/B7/B8/B20/B28 FDD set plus the B38/B40/B41 TDD set — and spot
# checked, not verified per device against a spec database. See TODO.md.

# Structured TAC pool. Each entry is verified against a public allocation
# database; see the header above for why that matters. Metadata drives the
# --brand / --type / --model filters, so adding an entry makes it selectable
# without touching the filtering code.
TAC_POOL = [
    {"tac": "35012276", "brand": "apple", "type": "phone", "model": "IPHONE 13 A2633",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35016811", "brand": "apple", "type": "phone", "model": "IPHONE 14 A2882",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35025753", "brand": "apple", "type": "phone", "model": "IPHONE 13 A2633",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35035296", "brand": "apple", "type": "phone", "model": "IPHONE 13 A2633",
     "fits": ['ep06e']},
    {"tac": "35051091", "brand": "apple", "type": "phone", "model": "IPHONE 14 A2882",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35072004", "brand": "apple", "type": "phone", "model": "IPHONE 14 A2881",
     "fits": ['ep06e']},
    {"tac": "35089945", "brand": "apple", "type": "phone", "model": "IPHONE 15 A2846",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35285287", "brand": "apple", "type": "phone", "model": "IPHONE 15 A3090",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35294597", "brand": "apple", "type": "phone", "model": "IPHONE 15 A3090",
     "fits": ['ep06e']},
    {"tac": "35674973", "brand": "samsung", "type": "phone", "model": "GALAXY S24 SM-S921U2024",
     "fits": ['em060k']},
    {"tac": "35733851", "brand": "samsung", "type": "phone", "model": "GALAXY S24 SM-S921U2024",
     "fits": ['em060k']},
    {"tac": "35870082", "brand": "samsung", "type": "phone", "model": "GALAXY S22 5G SM-S901B/DS2022",
     "fits": ['ep06e']},
    {"tac": "35888163", "brand": "samsung", "type": "phone", "model": "GALAXY A53 5G SM-A536B/DS2022",
     "fits": ['ep06e']},
    {"tac": "35896224", "brand": "samsung", "type": "phone", "model": "GALAXY S23 SM-S911U US",
     "fits": ['em060k']},
    {"tac": "35899214", "brand": "samsung", "type": "phone", "model": "GALAXY S22 5G SM-S901B/DS2022",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35909947", "brand": "google", "type": "phone", "model": "PIXEL 7",
     "fits": ['em060k']},
    {"tac": "35914561", "brand": "google", "type": "phone", "model": "PIXEL 7",
     "fits": ['em060k']},
    {"tac": "35918923", "brand": "samsung", "type": "phone", "model": "GALAXY S21 5G SM-G991B/DS2021",
     "fits": ['ep06e']},
    {"tac": "35927329", "brand": "samsung", "type": "phone", "model": "GALAXY A53 5G SM-A536B/DS2022",
     "fits": ['ep06e']},
    {"tac": "35940085", "brand": "samsung", "type": "phone", "model": "GALAXY S23 SM-S911U US",
     "fits": ['em060k']},
    {"tac": "35944533", "brand": "google", "type": "phone", "model": "PIXEL 8",
     "fits": ['em060k']},
    {"tac": "35955719", "brand": "samsung", "type": "phone", "model": "GALAXY S22 5G SM-S901B/DS2022",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35958628", "brand": "samsung", "type": "phone", "model": "GALAXY S23 SM-S911B/DS2023",
     "fits": ['ep06e']},
    {"tac": "35963468", "brand": "samsung", "type": "phone", "model": "GALAXY A53 5G SM-A536B/DS2022",
     "fits": ['ep06e']},
    {"tac": "35965699", "brand": "samsung", "type": "phone", "model": "GALAXY S23 SM-S911B/DS2023",
     "fits": ['ep06e']},
    {"tac": "35965882", "brand": "samsung", "type": "phone", "model": "GALAXY A53 5G SM-A536E/DS2022",
     "fits": ['em060k']},
    {"tac": "35966376", "brand": "samsung", "type": "phone", "model": "GALAXY S21 5G SM-G991U US",
     "fits": ['em060k']},
    {"tac": "35966984", "brand": "samsung", "type": "phone", "model": "GALAXY S21 5G SM-G991B/DS2021",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35967054", "brand": "samsung", "type": "phone", "model": "GALAXY S22 5G SM-S901U US",
     "fits": ['em060k']},
    {"tac": "35969437", "brand": "samsung", "type": "phone", "model": "GALAXY S22 5G SM-S901U US",
     "fits": ['em060k']},
    {"tac": "35971387", "brand": "samsung", "type": "phone", "model": "GALAXY S21 5G SM-G991B/DS2021",
     "fits": ['ep06e', 'em060k']},
    {"tac": "35973922", "brand": "samsung", "type": "phone", "model": "GALAXY S23 SM-S911B/DS2023",
     "fits": ['ep06e']},
    {"tac": "35983173", "brand": "google", "type": "phone", "model": "PIXEL 8",
     "fits": ['em060k']},
    {"tac": "35985621", "brand": "samsung", "type": "phone", "model": "GALAXY A53 5G SM-A536U US",
     "fits": ['em060k']},
    {"tac": "35985931", "brand": "samsung", "type": "phone", "model": "GALAXY S21 5G SM-G991U US",
     "fits": ['em060k']},
    {"tac": "86385606", "brand": "xiaomi", "type": "phone", "model": "REDMI NOTE 11 PRO+",
     "fits": ['ep06e']},
    {"tac": "86804506", "brand": "xiaomi", "type": "phone", "model": "REDMI NOTE 11 PRO+",
     "fits": ['ep06e']},
    {"tac": "86862206", "brand": "xiaomi", "type": "phone", "model": "REDMI NOTE 11 PRO+",
     "fits": ['ep06e']},
    {"tac": "35996594", "brand": "glinet", "type": "hotspot",
     "model": "4G LTE WIRELESS", "fits": ["native"]},
]


def pool_for(variant=None, brand=None, dtype=None, model=None):
    """Prefixes matching every filter given. Empty means nothing matched."""
    out = []
    for e in TAC_POOL:
        if variant and variant not in e["fits"]:
            continue
        if brand and e["brand"] != brand.lower():
            continue
        if dtype and e["type"] != dtype.lower():
            continue
        if model and model.lower() not in e["model"].lower():
            continue
        out.append(e["tac"])
    return out


def describe_pool():
    """Human-readable inventory, for --list-pool."""
    from collections import Counter
    lines = ["Verified TAC pool: %d entries" % len(TAC_POOL), ""]
    for key, label in (("brand", "brands"), ("type", "types")):
        c = Counter(e[key] for e in TAC_POOL)
        lines.append("%-8s %s" % (label + ":", "  ".join(
            "%s(%d)" % (k, n) for k, n in sorted(c.items()))))
    lines.append("")
    lines.append("%-10s %-9s %-8s %s" % ("TAC", "BRAND", "TYPE", "MODEL"))
    for e in sorted(TAC_POOL, key=lambda x: (x["brand"], x["model"], x["tac"])):
        lines.append("%-10s %-9s %-8s %s" % (e["tac"], e["brand"], e["type"], e["model"]))
    return "\n".join(lines)


# Default: combined list (fallback if modem not detected)
imei_prefix = pool_for(variant="ep06e")

verbose = False
mode = None

# Serial global vars
def _detect_at_tty(default='/dev/ttyUSB3'):
    """Return an AT-capable port, trying the usual one first.

    Both /dev/ttyUSB2 and /dev/ttyUSB3 answer AT on the EM060K-GL, so the
    inherited default is fine and probing every port up front would only add
    seconds to a script the toggle path runs under a timeout. Probe only when
    the default is silent.
    """
    import glob as _glob

    def answers(dev):
        try:
            with serial.Serial(dev, BAUDRATE, timeout=1, exclusive=True) as probe:
                probe.write(b'AT+GSN\r')
                return bool(re.search(b'[0-9]{14,15}', probe.read(64)))
        except Exception:
            return False

    if answers(default):
        return default
    for dev in sorted(_glob.glob('/dev/ttyUSB*')):
        if dev != default and answers(dev):
            return dev
    return default


TTY = '/dev/ttyUSB3'  # replaced at startup by _detect_at_tty()
BAUDRATE = 9600
TIMEOUT = 3


def get_imsi():
    if (verbose):
        print(f'Obtaining Serial {TTY} with timeout {TIMEOUT}...')
    with serial.Serial(TTY, BAUDRATE, timeout=TIMEOUT, exclusive=True) as ser:
        if (verbose):
            print('Getting IMSI')
        ser.write(b'AT+CIMI\r')
        # TODO: read loop until we have 'enough' of what to expect
        output = ser.read(64)

    if (verbose):
        print(b'Output of AT+CIMI (Retrieve IMSI) command: ' + output)
        print('Output is of type: ' + str(type(output)))
    imsi_d = re.findall(b'[0-9]{15}', output)
    if (verbose):
        print("TEST: Read IMSI is", imsi_d)

    return b"".join(imsi_d)


def set_imei(imei):
    with serial.Serial(TTY, BAUDRATE, timeout=TIMEOUT, exclusive=True) as ser:
        cmd = b'AT+EGMR=1,7,\"'+imei.encode()+b'\"\r'
        ser.write(cmd)
        output = ser.read(64)

    if (verbose):
        print(cmd)
        print(b'Output of AT+EGMR (Set IMEI) command: ' + output)
        print('Output is of type: ' + str(type(output)))

    new_imei = get_imei()
    if (verbose):
        print(b"New IMEI: "+new_imei+b" Old IMEI: "+imei.encode())

    if new_imei == imei.encode():
        print("IMEI has been successfully changed.")
        sync_esim_imei(imei)
        restart_modem_daemon()
        return True
    else:
        print("IMEI has not been successfully changed.")
        return False


def restart_modem_daemon():
    """Bring GL's AT broker back up after we have held the port exclusively.

    /usr/bin/modem_AT owns the serial port and everything else on the device —
    gl_modem, red-merle-ctl status, both dashboards, the boot sequence — talks
    to the modem through it. Opening the port with exclusive=True to write the
    IMEI knocks it over, and it does not come back on its own: gl_modem then
    hangs forever and the router looks like it lost its modem. Verified on
    hardware, including that relaunching the binary restores service.
    """
    import subprocess as _sp
    try:
        out = _sp.run(['ps', 'w'], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return
    line = next((l for l in out.splitlines() if '/usr/bin/modem_AT' in l), None)
    if line is None:
        return
    if _sp.run(['pgrep', '-f', 'modem_AT'], capture_output=True).returncode == 0:
        args = line.split('/usr/bin/modem_AT', 1)[1].split()
        try:
            _sp.run(['killall', 'modem_AT'], capture_output=True, timeout=5)
            _sp.Popen(['/usr/bin/modem_AT'] + args,
                      stdout=_sp.DEVNULL, stderr=_sp.DEVNULL)
        except Exception as exc:
            print('Could not restart modem_AT: %s' % exc, file=sys.stderr)


def sync_esim_imei(imei, esim_dir='/root/esim'):
    """Keep GL's eSIM LPA state from outliving the IMEI we just replaced.

    The LPA daemon (/usr/bin/lpa_mips_*) caches the IMEI it last saw in
    /root/esim/imei and logs to /root/esim/log.txt. Both survive reboots, so
    an untouched /root/esim/imei is a plaintext copy of the previous - often
    the factory - IMEI sitting on disk while the modem reports a spoofed one.
    Exactly the correlation red-merle exists to remove.

    Doing this here rather than in the shell wrappers covers every caller:
    the interactive CLI, the physical toggle, red-merle-ctl, and both web
    dashboards all set the IMEI through set_imei().

    esim_dir is a parameter so the wipe can be exercised against a scratch
    directory instead of the live one.
    """
    if not os.path.isdir(esim_dir):
        return
    try:
        path = os.path.join(esim_dir, 'imei')
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as fh:
            fh.write(imei + '\n')
        # O_CREAT's mode only applies when the file did not exist yet, and this
        # one usually does — set it explicitly so it can never stay world-readable.
        os.chmod(path, 0o600)
    except OSError as exc:
        print('Could not update %s/imei: %s' % (esim_dir, exc), file=sys.stderr)

    log = os.path.join(esim_dir, 'log.txt')
    if os.path.exists(log):
        # shred is a package dependency; fall back to a plain overwrite so a
        # missing binary still leaves no readable trace behind.
        try:
            subprocess.run(['shred', '-u', log], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            try:
                with open(log, 'r+b') as fh:
                    length = os.fstat(fh.fileno()).st_size
                    fh.write(b'\x00' * length)
                    fh.flush()
                    os.fsync(fh.fileno())
                os.unlink(log)
            except OSError as exc:
                print('Could not wipe %s: %s' % (log, exc), file=sys.stderr)


def get_imei():
    with serial.Serial(TTY, BAUDRATE, timeout=TIMEOUT, exclusive=True) as ser:
        ser.write(b'AT+GSN\r')
        output = ser.read(64)

    if (verbose):
        print(b'Output of AT+GSN (Retrieve IMEI) command: ' + output)
        print('Output is of type: ' + str(type(output)))
    imei_d = re.findall(b'[0-9]{15}', output)
    if (verbose):
        print("TEST: Read IMEI is", imei_d)

    return b"".join(imei_d)


def generate_imei(imei_prefix, imsi_d):
    # In deterministic mode we seed the RNG with the IMSI.
    # As a consequence we will always generate the same IMEI for a given IMSI
    if (mode == Modes.DETERMINISTIC):
        random.seed(imsi_d)

    # We choose a random prefix from the predefined list.
    # Then we fill the rest with random characters
    imei = random.choice(imei_prefix)
    if (verbose):
        print(f"IMEI prefix: {imei}")
    random_part_length = imei_length - len(imei)
    if (verbose):
        print(f"Length of the random IMEI part: {random_part_length}")
    imei += "".join(random.choices(string.digits, k=random_part_length))
    if (verbose):
        print(f"IMEI without validation digit: {imei}")

    # calculate validation digit
    # Double each second digit in the IMEI: 4 18 0 2 5 8 2 0 3 4 3 14 5 2
    # (excluding the validation digit)

    iteration_1 = "".join([c if i % 2 == 0 else str(2*int(c)) for i, c in enumerate(imei)])

    # Separate this number into single digits: 4 1 8 0 2 5 8 2 0 3 4 3 1 4 5 2
    # (notice that 18 and 14 have been split).
    # Add up all the numbers: 4+1+8+0+2+5+8+2+0+3+4+3+1+4+5+2 = 52

    sum = reduce((lambda a, b: int(a) + int(b)), iteration_1)

    # Take your resulting number, remember it, and round it up to the nearest
    # multiple of ten: 60.
    # Subtract your original number from the rounded-up number: 60 - 52 = 8.

    validation_digit = (10 - int(str(sum)[-1])) % 10
    if (verbose):
        print(f"Validation digit: {validation_digit}")

    imei = str(imei) + str(validation_digit)
    if (verbose):
        print(f"Resulting IMEI: {imei}")

    return imei


def validate_imei(imei):
    # IMEI must be 15 digits (14 + check digit)
    if len(imei) != 15 or not imei.isdigit():
        print(f"NOT A VALID IMEI: {imei} - IMEI must be 15 digits")
        return False
    # cut off last digit
    validation_digit = int(imei[-1])
    imei_verify = imei[0:14]
    if (verbose):
        print(imei_verify)

    # Double each second digit in the IMEI
    iteration_1 = "".join([c if i % 2 == 0 else str(2*int(c)) for i, c in enumerate(imei_verify)])

    # Separate this number into single digits and add them up
    sum = reduce((lambda a, b: int(a) + int(b)), iteration_1)
    if (verbose):
        print(sum)

    # Take your resulting number, remember it, and round it up to the nearest
    # multiple of ten.
    # Subtract your original number from the rounded-up number.
    validation_digit_verify = (10 - int(str(sum)[-1])) % 10
    if (verbose):
        print(validation_digit_verify)

    if validation_digit == validation_digit_verify:
        print(f"{imei} is CORRECT")
        return True

    print(f"NOT A VALID IMEI: {imei}")
    return False


def detect_modem_prefixes(native=False, brand=None, dtype=None, model=None):
    """Pick the prefix list: modem variant first, then any operator filters."""
    global imei_prefix
    variant = "native" if native else None
    if not native:
        try:
            with serial.Serial(TTY, BAUDRATE, timeout=TIMEOUT, exclusive=True) as ser:
                ser.write(b'AT+CGMM\r')
                output = ser.read(128).decode(errors='ignore')
            if 'EM060K' in output or 'EM05' in output:
                variant = "em060k"
                if verbose:
                    print("Detected EM060K/EM05 modem (Mudi V2) - global TAC pool")
            elif 'EP06' in output or 'EG06' in output or 'EC25' in output:
                variant = "ep06e"
                if verbose:
                    print("Detected EP06/EG06 modem (Mudi V1) - EMEA TAC pool")
            else:
                variant = "ep06e"
                if verbose:
                    print("Unknown modem (%s) - defaulting to EMEA TAC pool"
                          % output.strip())
        except Exception:
            variant = "ep06e"
            if verbose:
                print("Could not detect modem - defaulting to EMEA TAC pool")

    picked = pool_for(variant=variant, brand=brand, dtype=dtype, model=model)
    if not picked:
        # Refuse rather than silently widening: an operator who asked for Apple
        # hotspots should be told none exist, not handed a Samsung phone.
        print("No TAC matches those filters. Try --list-pool to see what exists.",
              file=sys.stderr)
        sys.exit(1)
    imei_prefix = picked
    if verbose:
        print("TAC pool: %d candidate(s)" % len(picked))


if __name__ == '__main__':
    args = ap.parse_args()
    if args.list_pool:
        print(describe_pool())
        sys.exit(0)
    if not args.generate_only:
        TTY = _detect_at_tty(TTY)
        if verbose:
            print('Modem AT port: %s' % TTY)
    imsi_d = None
    if args.verbose:
        verbose = args.verbose

    # Select the TAC list. Native needs no modem round trip, and must still
    # apply under --generate-only, which skips detection.
    if args.tac:
        if not re.fullmatch(r'\d{8}', args.tac):
            print("TAC must be exactly 8 digits")
            sys.exit(1)
        imei_prefix = [args.tac]
        print("Using operator-supplied TAC %s. Nothing verifies that this "
              "device could report the capabilities this modem does." % args.tac)
    elif args.native or args.brand or args.dtype or args.model \
            or not args.generate_only:
        detect_modem_prefixes(native=args.native, brand=args.brand,
                              dtype=args.dtype, model=args.model)

    try:
        if args.deterministic:
            mode = Modes.DETERMINISTIC
            imsi_d = get_imsi()
        if args.random:
            mode = Modes.RANDOM
        if args.static is not None:
            mode = Modes.STATIC
            static_imei = args.static

        if mode == Modes.STATIC:
            if validate_imei(static_imei):
                if not args.generate_only:
                    if not set_imei(static_imei):
                        exit(-1)
            else:
                exit(-1)
        else:
            imei = generate_imei(imei_prefix, imsi_d)
            if (verbose):
                print(f"Generated new IMEI: {imei}")
            if not args.generate_only:
                if not set_imei(imei):
                    exit(-1)
    except (serial.SerialException, OSError) as e:
        # Modem serial port unavailable or unplugged mid-operation:
        # fail with a clear message instead of a traceback
        print(f"Error: could not talk to the modem via {TTY} ({e})", file=sys.stderr)
        exit(2)

    exit(0)
