#!/usr/bin/env python3
import random
import string
import argparse
import serial
import re
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

# Example IMEI: 490154203237518
imei_length = 14  # without validation digit

# TAC prefixes curated to match modem frequency bands.
# Each TAC corresponds to a real high-volume device whose LTE band profile
# is a superset of the Mudi's modem bands, preventing carrier fingerprinting.

# EP06-E (Mudi V1 EMEA): must support B1,B3,B5,B7,B8,B20,B28,B38,B40,B41
imei_prefix_ep06e = [
    # MiFi/Hotspots (same device class - least suspicious)
    "86806903",  # Huawei E5787s-33a (Cat6 hotspot)
    "86735402",  # Huawei E5885Ls-93a (Cat6 hotspot)
    "35855908",  # Netgear Nighthawk M1 MR1100
    "35236208",  # Netgear Nighthawk M2 MR2100
    "86119702",  # Huawei E5788u-96a (Cat16 hotspot)
    # Samsung Galaxy A series global (massive volume)
    "35260911",  # Galaxy A53 5G SM-A536B
    "35260910",  # Galaxy A53 5G SM-A536B/DS
    "35455312",  # Galaxy A54 5G SM-A546B
    "35455311",  # Galaxy A54 5G SM-A546B/DS
    "35191610",  # Galaxy A52 SM-A525F
    "35238106",  # Galaxy A33 5G SM-A336B
    "35854706",  # Galaxy A34 5G SM-A346B
    # Samsung Galaxy S series global
    "35332211",  # Galaxy S21 5G SM-G991B
    "35695812",  # Galaxy S22 SM-S901B
    "35524911",  # Galaxy S23 SM-S911B
    # iPhone global/EMEA
    "35397510",  # iPhone 13 A2631
    "35407710",  # iPhone 13 Pro A2638
    "35517811",  # iPhone 14 A2882
    "35674012",  # iPhone 15 A3090
    "35320810",  # iPhone 12 A2403
    # Xiaomi global
    "86388103",  # Xiaomi 12 Pro Global
    "86154803",  # Xiaomi Redmi Note 11 Pro Global
    "86513704",  # Xiaomi Redmi Note 12 Pro Global
    "86826804",  # Xiaomi 13 Global
]

# EM060K-GL (Mudi V2 Global): broad band support, most flagships qualify
imei_prefix_em060k = [
    # MiFi/Hotspots
    "35855908",  # Netgear Nighthawk M1 MR1100
    "35236208",  # Netgear Nighthawk M2 MR2100
    "35348712",  # Netgear Nighthawk M5 MR5200
    "35498010",  # Inseego MiFi M2000
    "86806903",  # Huawei E5787s-33a
    # Samsung US (broadest band coverage)
    "35332209",  # Galaxy S21 5G SM-G991U
    "35695809",  # Galaxy S22 SM-S901U
    "35524909",  # Galaxy S23 SM-S911U
    "35732811",  # Galaxy S24 SM-S921U
    "35260909",  # Galaxy A53 5G SM-A536U
    "35455310",  # Galaxy A54 5G SM-A546U
    # Samsung Global (also valid)
    "35332211",  # Galaxy S21 5G SM-G991B
    "35695812",  # Galaxy S22 SM-S901B
    "35260911",  # Galaxy A53 5G SM-A536B
    "35524911",  # Galaxy S23 SM-S911B
    # iPhone US (near-total band superset)
    "35395610",  # iPhone 13 A2482
    "35483521",  # iPhone 14 A2649
    "35674009",  # iPhone 15 A2846
    "35320811",  # iPhone 12 A2172
    "35758512",  # iPhone 15 Pro Max A2849
    # Google Pixel US
    "35824011",  # Pixel 7
    "35824010",  # Pixel 7 Pro
    "35909912",  # Pixel 8
    # Xiaomi global
    "86388103",  # Xiaomi 12 Pro Global
    "86826804",  # Xiaomi 13 Global
]

# Default: combined list (fallback if modem not detected)
imei_prefix = imei_prefix_ep06e

verbose = False
mode = None

# Serial global vars
TTY = '/dev/ttyUSB3'
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
        return True
    else:
        print("IMEI has not been successfully changed.")
        return False


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


def detect_modem_prefixes():
    """Auto-detect modem variant and select matching TAC prefix list."""
    global imei_prefix
    try:
        with serial.Serial(TTY, BAUDRATE, timeout=TIMEOUT, exclusive=True) as ser:
            ser.write(b'AT+CGMM\r')
            output = ser.read(128).decode(errors='ignore')
        if 'EM060K' in output or 'EM05' in output:
            imei_prefix = imei_prefix_em060k
            if verbose:
                print("Detected EM060K/EM05 modem (Mudi V2) - using global TAC list")
        elif 'EP06' in output or 'EG06' in output or 'EC25' in output:
            imei_prefix = imei_prefix_ep06e
            if verbose:
                print("Detected EP06/EG06 modem (Mudi V1) - using EMEA TAC list")
        else:
            imei_prefix = imei_prefix_ep06e
            if verbose:
                print(f"Unknown modem ({output.strip()}) - using default EMEA TAC list")
    except Exception:
        if verbose:
            print("Could not detect modem - using default EMEA TAC list")


if __name__ == '__main__':
    args = ap.parse_args()
    imsi_d = None
    if args.verbose:
        verbose = args.verbose

    # Auto-detect modem and select TAC list
    if not args.generate_only:
        detect_modem_prefixes()

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
            set_imei(static_imei)
        else:
            exit(-1)
    else:
        imei = generate_imei(imei_prefix, imsi_d)
        if (verbose):
            print(f"Generated new IMEI: {imei}")
        if not args.generate_only:
            if not set_imei(imei):
                exit(-1)

    exit(0)
