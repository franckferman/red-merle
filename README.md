# red-merle

The *red-merle* software package enhances anonymity and reduces forensic traceability of the **GL-E750 / Mudi 4G mobile wi-fi router ("Mudi router")**. It is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs with additional features and continued maintenance.

*red-merle* addresses the traceability drawbacks of the Mudi router by adding the following features:

1. Mobile Equipment Identity (IMEI) changer (random, deterministic or static)
2. Media Access Control (MAC) address log wiper
3. Basic Service Set Identifier (BSSID) randomization
4. WAN MAC address randomization

## Threat model

*red-merle*'s protections are layered. Their relevance depends on who you are defending against:

**Carrier-level analytics** (the most common threat for journalists and activists): carriers log which IMEI connects to which cell tower, on which frequency band, at what time. An analyst searching for spoofed IMEIs can filter by:
1. Known blue-merle TAC prefixes (16 fixed values, public on GitHub)
2. Frequency band mismatch between the TAC's expected device and the actual connection
3. Serial number digit patterns (no repeated digits = statistical anomaly)

*red-merle* defeats all three filters: band-aligned TACs, expanded prefix pool (24+ per modem variant), and corrected serial entropy.

**Device seizure** (law enforcement, border crossing, theft): without log wiping, `logread | grep merle` on a seized Mudi reveals the complete IMEI change history with timestamps. *red-merle* wipes system logs at boot, after each IMEI change, and at shutdown, leaving no forensic trace of past identities.

**Silent carrier geolocation** (intelligence services, lawful interception): carriers can request GPS coordinates from the modem via LPP/SUPL/RRLP without any user-visible indication. *red-merle* disables this at every boot.

**Retrospective network analysis** (the hardest to defend against): an adversary with months of carrier logs can correlate sessions by timing, cell tower patterns, and traffic fingerprints even across IMEI changes. *red-merle* mitigates some of this (DNS flush, MAC randomization) but cannot fully prevent time-based correlation. The standard advice remains: **change your IMEI, change your SIM, and change your location before reconnecting**.

## Hardening modes and security paradoxes

*red-merle* offers two distinct operational modes that represent different philosophies in privacy protection: **anonymity through uniformity** versus **security through attack surface reduction**.

### The fundamental paradox

Modern privacy tools face a classic dilemma: the more secure you make your device, the more identifiable it becomes. This creates a trade-off between **individual security** and **population-level anonymity**.

```
Normal user population (50M subscribers):
[VoLTE: ON] [SUPL: ON] [OMA-DM: ON] [Bands: 4G/3G/2G]

Hardened red-merle user:
[VoLTE: OFF] [SUPL: OFF] [OMA-DM: OFF] [Bands: 4G only]
= Unique network signature detectable by carrier analysis
```

### Stealth mode: Invisible protection

**Philosophy**: Blend in with the normal user population while applying network-level protections.

| Protection | Carrier visibility | Effectiveness |
|------------|-------------------|---------------|
| iptables blocking (SUPL/OMA-DM ports) | ❌ Invisible | ✅ Blocks tracking requests |
| MAC randomization | ❌ Local only | ✅ Prevents WiFi correlation |
| Log sanitization | ❌ Device-local | ✅ Prevents forensic recovery |
| AT command modifications | ❌ **None applied** | ❌ Modem features remain active |

**Advantages**:
- Indistinguishable from normal users in carrier logs
- No technical profiling risk ("this user knows about privacy tools")
- Optimal against mass surveillance and bulk collection
- Safe for use in authoritarian contexts where technical sophistication is flagged

**Trade-offs**:
- GPS/SUPL requests still reach the modem (blocked at network layer)
- IMS/VoLTE metadata collection continues
- Vulnerable to sophisticated modem-level positioning requests
- Partial protection against IMSI catchers (no 4G-only enforcement)

### Hardening mode: Maximum protection

**Philosophy**: Disable all tracking capabilities at the modem level, accepting network-level detectability.

| Protection | Carrier visibility | Effectiveness |
|------------|-------------------|---------------|
| All stealth protections | ❌ Invisible | ✅ Same as stealth |
| GPS/SUPL AT commands | ✅ **Highly visible** | ✅ Complete modem-level blocking |
| IMS/VoLTE disabling | ✅ **Visible** | ✅ Prevents metadata collection |
| 4G-only enforcement | ✅ **Visible** | ✅ Blocks IMSI catcher downgrade attacks |
| Dynamic modem detection | ❌ Invisible | ✅ Optimized per hardware variant |

**Advantages**:
- Maximum attack surface reduction
- Complete protection against silent positioning
- Resistance to IMSI catchers and 2G/3G vulnerabilities
- Optimal for targeted threats and known surveillance

**Trade-offs**:
- Creates unique "privacy-conscious user" network signature
- Correlatable with other red-merle users through behavioral analysis
- May trigger additional scrutiny from sophisticated adversaries
- Potentially counterproductive in mass surveillance contexts

### Decision framework

**Choose stealth mode when**:
- Your threat model involves **passive mass surveillance**
- You want to avoid being flagged as a "person of technical interest"
- You're operating in environments where privacy tools usage is itself suspicious
- You're not currently under targeted investigation
- You prefer **anonymity over maximum security**

**Choose hardening mode when**:
- You're facing **targeted technical threats**
- You've detected IMSI catchers or forced network downgrades
- You're already under investigation (technical sophistication already known)
- You're in high-risk situations where location privacy is critical
- You prefer **maximum security over anonymity**

**Switch dynamically**:
```sh
# Default: invisible protection
red-merle-mode-switch stealth

# Escalate when threats become targeted
red-merle-mode-switch hardening

# Return to stealth when context changes
red-merle-mode-switch stealth
```

### The adoption paradox

The effectiveness of each mode depends on **population-level adoption patterns**:

| User base size | Hardening mode detectability | Stealth mode necessity |
|----------------|------------------------------|------------------------|
| <1,000 users | Highly detectable signature | Essential for most users |
| 1K-100K users | Detectable but with noise | Recommended default |
| 1M+ users | Statistical background | Stealth becomes optional |
| Mainstream adoption | New "normal" baseline | Hardening becomes default |

**Current reality (2024)**: *red-merle* has a small, technical user base. Hardening mode creates a detectable signature that could be used to profile privacy-conscious users. This may change as adoption scales.

**Strategic implications**:
- **Individual users** should default to stealth mode unless facing specific technical threats
- **Community growth** benefits everyone by diluting hardening mode signatures
- **Long-term** success depends on making privacy protection indistinguishable from normal usage

### Honest assessment

Neither mode provides perfect protection. Both involve trade-offs that users must understand:

**Stealth mode limitations**:
- Relies on network-layer blocking that sophisticated adversaries might circumvent
- Provides incomplete protection against state-level threats with modem backdoors
- May be less effective against targeted attacks using unknown positioning vectors

**Hardening mode limitations**:
- Current user base size makes detection feasible for capable adversaries
- May actually increase surveillance attention by signaling privacy consciousness
- Could facilitate correlation with other red-merle users through signature matching

**Universal limitations**:
- Cannot prevent retrospective analysis of connection patterns and timing
- SIM card and network registration remain primary identity vectors
- Physical device seizure may reveal usage regardless of mode
- Advanced persistent threats may have capabilities beyond documented protocols

### Recommendation

Start with **stealth mode** as the default. It provides meaningful protection against the most common threats (mass surveillance, bulk collection) while maintaining operational security through anonymity. Escalate to hardening mode only when facing specific technical threats that justify the increased detectability risk.

The most effective privacy strategy combines technological protection with operational security: change your IMEI, change your SIM, and change your physical location. Technology alone cannot solve the privacy problem, but it can raise the cost of surveillance and reduce the scope of data collection.

## Compatibility

Verified with GL-E750 Mudi firmware version **4.3.26**. Firmware versions 4.x should work but are not tested and will display a warning during installation.

### Dependencies

- `luci-base`
- `gl-sdk4-mcu`
- `coreutils-shred`
- `python3-pyserial`

## Installation

### Online install

The online install method requires an **active Internet connection** on your Mudi to download dependencies.

Download the [latest `.ipk` release](https://github.com/franckferman/red-merle/releases/latest) and copy it onto your Mudi (e.g. via `scp`), preferably into `/tmp`. Then install:

```sh
scp red-merle_*.ipk root@192.168.8.1:/tmp/
ssh root@192.168.8.1

opkg update
opkg install /tmp/red-merle*.ipk
```

To upgrade, download the newest `.ipk` and reinstall:

```sh
opkg install --force-reinstall /tmp/red-merle*.ipk
```

### Offline install

The offline install method does **not need an active Internet connection** on your Mudi.

Download the [latest offline release package](https://github.com/franckferman/red-merle/releases/latest) (the `_offline_install.zip` file), then:

```sh
# On your computer (connected to the Mudi via WiFi / LAN)
unzip red-merle_offline_install.zip

# Copy the offline package to your Mudi
# -O might be needed due to the SSH daemon used by the Mudi
scp -O -r red-merle_offline_install root@192.168.8.1:/tmp

# Connect to Mudi via SSH
ssh root@192.168.8.1

# Install dependencies and red-merle
cd /tmp/red-merle_offline_install
./install.sh
```

### Quick build & install (no SDK)

If you prefer to build from source:

```sh
git clone https://github.com/franckferman/red-merle.git
cd red-merle

# Build the .ipk locally
./build.sh

# Deploy to Mudi via SSH (default IP: 192.168.8.1)
./build.sh install

# Or specify a custom IP
MUDI_IP=10.0.0.1 ./build.sh install
```

### SDK build (same as CI)

```sh
./build.sh sdk-build
```

This downloads the OpenWrt 23.05.0 SDK for ath79/nand (~200MB) and builds the package exactly like the CI pipeline does.

## Usage

You may initiate an IMEI update in three different ways:

1. **CLI**: via SSH on the command line
2. **Toggle**: using the Mudi's physical toggle switch
3. **Web**: via the LuCI web interface

### CLI

Connect to the device via SSH, then execute:

```sh
red-merle
```

The command guides you through the process of **changing your SIM card**. It supports three IMEI modes:

- **Random** (`-r`): generates a fully random IMEI
- **Deterministic** (`-d`): generates a pseudo-random IMEI seeded by the inserted SIM's IMSI (same IMSI always produces the same IMEI, regardless of the device)
- **Static** (`-s`): sets a user-provided IMEI (validated with Luhn checksum)

We advise you to **reboot the device** and **change location** after changing the IMEI.

### Toggle

This is a two-stage process using the Mudi's physical switch.

**Stage 1**: Flip the switch. The modem radio is disabled, a temporary random IMEI is set (preventing your old IMEI from being seen with the new SIM), and the display prompts you to **replace the SIM card**.

**Stage 2**: After swapping the SIM, flip the switch again. The modem reads the new IMSI, a final random IMEI is set, and the device **powers off** automatically. **Change location** before booting again.

A 60-second rate limit prevents accidental rapid toggles.

### Web

Open the LuCI interface from `System` > `Advanced Settings`. Find the `Red Merle` settings under the `Network` tab. The interface displays the current IMEI and IMSI and provides a **"SIM swap..."** button.

**Shutdown the device** once the process is complete, **swap your SIM card** and **change location** before booting again.

## What it does at boot

On every boot, *red-merle* automatically performs the following (before network comes up):

| Action | Purpose |
|---|---|
| Log wipe | Clears syslog, dmesg, shell history and tmp logs left over from the previous session (protects against crash or abrupt shutdown before post-IMEI-change wipe could run) |
| BSSID randomization | New random MAC for both WiFi interfaces (2.4 + 5 GHz), defeating WiFi geolocation databases (WiGLE, Google, Apple) |
| WAN MAC randomization | New random MAC for the upstream-facing interface, preventing session correlation across locations |
| Carrier GPS disable | Sends AT commands to refuse silent LPP/SUPL/RRLP positioning requests from the carrier. Re-applied every boot because the setting is non-persistent on some Quectel firmware versions |
| Client database volatility | The `/etc/oui-tertf` client database is shredded and replaced with a tmpfs mount. Connected device history is kept in RAM only and lost on reboot |

## Building

This repository contains a CI workflow (`.github/workflows/ci.yml`) that auto-builds the `.ipk` using the OpenWrt 23.05.0 SDK on every push.

You can also build locally:

```sh
# Quick build (no SDK, creates a generic .ipk)
./build.sh

# Full SDK build (same as CI, creates an architecture-specific .ipk)
./build.sh sdk-build

# Clean build artifacts
./build.sh clean
```

Or set up a full OpenWrt development environment:

```sh
git clone https://github.com/openwrt/openwrt
cd openwrt
git clone https://github.com/franckferman/red-merle package/red-merle
./scripts/feeds update -a && ./scripts/feeds install -a
make distclean && make clean
make menuconfig
    # Target System: Atheros ATH79
    # Subtarget: Generic Devices with NAND flash
    # Target Profile: GL.iNet GL-E750
    # In Utilities, select <M> for red-merle
    # Save
make package/red-merle/compile
```

The package will be in `./bin/packages/mips_24kc/base/`.

## Implementation details

### IMEI randomization

An IMEI (International Mobile Equipment Identity) is a 15-digit identifier structured as:

```
[TAC: 8 digits][Serial: 6 digits][Luhn check: 1 digit]
```

- **TAC** (Type Allocation Code): assigned by the GSMA, identifies manufacturer + model + hardware revision. Carriers maintain TAC databases with per-device metadata including supported frequency bands.
- **Serial**: 6 digits assigned by the manufacturer, typically sequential.
- **Luhn check digit**: deterministic checksum computed from the first 14 digits using the [Luhn algorithm](https://en.wikipedia.org/wiki/Luhn_algorithm).

The Mudi router's baseband is a Quectel EP06-E/A (V1) or EM060K-GL (V2) LTE module. The IMEI is changed via the AT command `AT+EGMR=1,7,"<IMEI>"` sent over serial (`/dev/ttyUSB3` at 9600 baud).

#### TAC prefix selection and frequency band alignment

**The problem with blue-merle:** blue-merle uses 16 hardcoded TAC prefixes corresponding to consumer phones (Samsung, Apple, etc.) whose LTE band profiles do not match the Mudi's modem. The EP06-E connects on TDD bands B38/B40/B41 that many of those phones do not support. A carrier cross-referencing the IMEI's TAC (which maps to a specific phone model) against the actual bands used for the connection can detect the mismatch.

This is documented in [blue-merle Issue #1](https://github.com/srlabs/blue-merle/issues/1), open since the project's creation. [PR #71](https://github.com/srlabs/blue-merle/pull/71) attempted to fix this by aligning TACs to the EM05-G module's frequency bands, but was closed without being merged. The issue has remained unresolved for over 4 years.

This likely happened because blue-merle originated as a security research proof-of-concept by SRLabs (published alongside an academic paper in 2022). The primary goal was to demonstrate that the Mudi's IMEI could be changed via AT commands, not to build a hardened OPSEC tool. The TAC prefixes were chosen to produce Luhn-valid IMEIs accepted by carriers, without verifying frequency band alignment. Band-level fingerprinting resistance is a concern that arises when defending against a real adversary with carrier-level access, not when writing a conference paper.

**red-merle's approach:** TAC prefixes are curated per modem variant. The function `detect_modem_prefixes()` sends `AT+CGMM` to the modem via serial at startup. The modem responds with its model identifier (e.g. "EP06-E" or "EM060K-GL"), and the script automatically selects the matching TAC list. The user does not need to configure anything.

Two separate lists are maintained:

- **EP06-E** (Mudi V1, EMEA bands B1/B3/B5/B7/B8/B20/B28/B32/B38/B40/B41): 24 TACs from devices whose band profile is a superset:
  - 5 MiFi/hotspots (Huawei E5787, E5885, E5788, Netgear Nighthawk M1/M2) - same device class as the Mudi, producing the least suspicious network profile (data-only, no voice/SMS)
  - 7 Samsung Galaxy A series global variants (A52, A33, A34, A53, A54) - tens of millions of units in circulation on European networks
  - 3 Samsung Galaxy S series global variants (S21, S22, S23)
  - 5 iPhones, international models (iPhone 12 through 15, A2xxx model numbers)
  - 4 Xiaomi global variants (12 Pro, Redmi Note 11/12 Pro, 13)

- **EM060K-GL** (Mudi V2, global bands): 25 TACs. The EM060K-GL's broad band support means most modern flagships qualify. The list includes US-market devices (Samsung US, iPhone US, Google Pixel) whose band profiles are the widest available, plus 5G hotspots (Netgear M5, Inseego M2000) and the same global devices from the EP06-E list.

If the modem is not recognized, the EP06-E list is used as a safe default.

#### Serial number generation and entropy analysis

All entropy in a generated IMEI resides in the 6-digit serial portion. The TAC is selected from a fixed list, and the Luhn digit is deterministic. The quality of the serial generation directly determines how distinguishable synthetic IMEIs are from legitimate ones.

**blue-merle uses `random.sample(string.digits, 6)`** - sampling *without replacement* from {0,1,...,9}. Think of it as drawing from a bag of marbles: you pull one out, it is gone from the bag, and you cannot draw it again. This is a partial permutation (arrangement):

```
A(n,k) = n! / (n-k)! = 10! / 4! = 151,200 possible outputs
```

The critical property: every generated serial has **all distinct digits**. "370591" is possible; "373593" is not, because "3" cannot be drawn twice.

**red-merle uses `random.choices(string.digits, k=6)`** - sampling *with replacement*. Think of it as rolling a 10-sided die: each roll is independent, and the same number can come up any number of times. "373593" is now possible, just like on real IMEIs.

```
|Omega| = n^k = 10^6 = 1,000,000 possible outputs
```

The entropy difference:

```
H_old  = log2(151,200) = 17.2 bits
H_new  = log2(1,000,000) = 19.9 bits
Gain: +2.7 bits (6.6x larger keyspace)
```

**Why this matters for detection:**

The probability that a uniformly random 6-digit number has no repeated digits is:

```
P(no repetition) = A(10,6) / 10^6 = 151,200 / 1,000,000 = 0.1512
```

In a legitimate IMEI population, roughly 15% of serials happen to have no repetitions. With blue-merle, **100%** of generated serials have no repetitions.

An analyst with access to a carrier EIR (Equipment Identity Register) or GSMA IMEI database can apply a simple statistical test:

```
H0: IMEI is legitimate (serial digits uniformly distributed)
H1: IMEI is generated by blue-merle (no digit repetition, ever)

P(N out of N without repetition | H0) = 0.1512^N
```

| Observations (N) | P-value under H0 | Conclusion |
|---|---|---|
| 1 | 0.1512 | Inconclusive |
| 3 | 0.00345 | Suspicious (p < 0.5%) |
| 5 | 0.0000784 | Detected (p < 0.01%) |
| 10 | 6.1 x 10^-9 | Certain |

With just 5 observed IMEIs sharing a blue-merle TAC prefix, the analyst rejects H0 at >99.99% confidence. Combined with other signals (data-only behavior, band mismatch), even a single IMEI becomes highly suspect.

With `random.choices`, ~85% of red-merle IMEIs contain repeated digits, matching the expected distribution. The repetition-based test no longer discriminates.

**Remaining limitations:** manufacturers assign serials sequentially (counters), not randomly. A truly exhaustive analysis comparing generated serials against known allocation ranges could still detect synthetic IMEIs, but this requires access to the proprietary GSMA TAC/serial database and is not a standard carrier operation.

#### IMEI leak prevention during SIM swap

To prevent IMEI leakage during SIM swap, the modem radio is disabled (`AT+CFUN=4`) before the SIM is removed, and a temporary random IMEI is set immediately. The final IMEI is only written after the new SIM is inserted and its IMSI is read.

![Figure 1. The router's radio is turned off and the IMEI is randomized between entries 70 and 80.](./IMEI%20randomization.png)

### Carrier GPS tracking protection

The Quectel modem's AGPS (Assisted GPS) is **enabled by default** out of the factory. The modem does not broadcast GPS continuously on its own, but when the carrier sends a positioning request via LPP (LTE Positioning Protocol), SUPL (Secure User Plane Location), or RRLP (Radio Resource LCS Protocol), the modem **responds automatically** with GPS coordinates. This exchange happens between the carrier and the baseband, with no notification or consent prompt visible to the user.

Carriers use this for:
- Emergency calls (E911/E112 legal obligations)
- Law enforcement location requests (lawful interception)
- Network optimization (subscriber density mapping)

GL.iNet does not disable this because the Mudi is marketed as a consumer router, not a privacy tool. blue-merle does not address it either.

*red-merle* disables assisted positioning at boot and after each IMEI change via AT commands:

```
AT+QGPSCFG="agpsposmode",0    # Refuse carrier positioning requests
AT+QGPSCFG="gpsnmeatype",0    # Disable NMEA sentence output
AT+QGPSCFG="suplver",0        # Disable SUPL protocol
```

These settings are non-persistent on some Quectel firmware versions (reset after modem power cycle), which is why *red-merle* re-applies them at every boot.

### Log sanitization

blue-merle writes IMEI changes in cleartext to syslog via `logger`:

```
red-merle-toggle: Changed IMEI from 352609114567893 to 354553127891234
red-merle-toggle: Finished with Stage 2
```

On OpenWrt, syslog persists in the `logd` ring buffer (readable via `logread`) and on some configurations writes to flash (`/var/log/messages`). A device seizure followed by `logread | grep merle` reveals the full IMEI change history with timestamps.

*red-merle* removes these `logger` calls entirely and performs a full log wipe at three points in the device lifecycle:

**At boot** (clears traces from a previous session that may have survived a crash or abrupt shutdown):
- Syslog ring buffer (`/etc/init.d/log restart`)
- Kernel ring buffer (`dmesg -c`)
- Shell command history (`/root/.ash_history` - contains `red-merle` commands, AT commands typed in SSH)
- Temporary log files (`/tmp/log/*`)

**After each IMEI change** (same wipe, plus eSIM logs):
- All of the above
- eSIM logs (`/root/esim/log.txt`)

**At shutdown** (ensures the device is clean if it never boots again, e.g. seizure while powered off):
- All of the above

### BSSID randomization

On each boot, *red-merle* generates a valid unicast MAC address and overrides the current BSSID for both `wlan0` and `wlan1` via OpenWrt UCI commands. WiFi is restarted to apply the change.

### WAN MAC randomization

A random MAC is generated and applied to the upstream WAN interface (`network.@device[1].macaddr`), preventing the Mudi from being tracked by upstream access points across reboots. This may interfere with MAC filtering if enabled on the upstream WiFi AP.

### Client database volatility

The client database at `/etc/oui-tertf` is securely deleted with `shred` on boot, then a `tmpfs` filesystem is mounted at that location. The `gl_clients` service is restarted so it writes to RAM only. Device seizure or flash memory forensics will not recover previously connected client MAC addresses.

### DNS cache flush

After each IMEI change, `dnsmasq` is restarted to clear the DNS cache. Stale DNS entries from a previous session could otherwise be used to correlate identities across IMEI changes.

## File structure

```
files/
├── etc/
│   ├── config/red-merle                         Config (UCI)
│   ├── gl-switch.d/sim.sh                       Toggle switch handler
│   └── init.d/
│       ├── red-merle                            Boot: MAC/BSSID randomization
│       └── volatile-client-macs                 Boot: client DB volatility
├── lib/red-merle/
│   ├── functions.sh                             Helper functions
│   ├── imei_generate.py                         IMEI generation + serial modem
│   └── luhn.lua                                 Luhn checksum
├── usr/
│   ├── bin/
│   │   ├── red-merle                            CLI SIM swap workflow
│   │   ├── red-merle-switch-stage1              Toggle stage 1
│   │   ├── red-merle-switch-stage2              Toggle stage 2
│   │   └── sim_switch                           State toggler
│   ├── libexec/red-merle                        RPC endpoint for LuCI
│   └── share/
│       ├── luci/menu.d/luci-app-red-merle.json  LuCI menu entry
│       └── rpcd/acl.d/luci-app-red-merle.json   LuCI permissions
└── www/luci-static/resources/view/red-merle.js  LuCI web interface
```

## Differences from blue-merle

*red-merle* is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs. Key changes:

### Security fixes

| Issue | blue-merle | red-merle |
|---|---|---|
| TAC/band fingerprinting | 16 generic TACs, band mismatch detectable by carriers ([Issue #1](https://github.com/srlabs/blue-merle/issues/1)) | 24+ TACs per modem variant, band-aligned to EP06-E and EM060K-GL |
| IMEI serial entropy | `random.sample` without replacement: 151,200 combinations (17.2 bits), detectable via repetition analysis | `random.choices` with replacement: 1,000,000 combinations (19.9 bits), statistically indistinguishable |
| Syslog IMEI leak | Writes old/new IMEI in cleartext to syslog (`logger "Changed IMEI from X to Y"`) | All logger calls removed, syslog/dmesg/history wiped after IMEI change |
| Carrier GPS tracking | Not addressed (LPP/SUPL/RRLP active) | Disabled at boot and after each IMEI change via AT+QGPSCFG |
| DNS correlation | Not addressed | dnsmasq restarted after IMEI change |
| IMEI validation | `validate_imei()` checks for 14 digits (incorrect, IMEI is 15 digits) | Fixed to validate 15-digit IMEI |

### Features

- **Modem auto-detection**: `AT+CGMM` identifies EP06/EM060K and selects matching TAC prefix list
- **Static IMEI mode** (`-s`): set a specific IMEI, validated with Luhn checksum
- **eSIM path handling**: updates `/root/esim/imei` and shreds eSIM logs
- **Quick build script** (`build.sh`): build `.ipk` without the full SDK
- **Automated releases**: CI builds `.ipk` + offline install zip on tag push
- **Toggle rate limiting**: 60-second minimum between switch actions

## License

BSD 3-Clause License. See [LICENSE.md](LICENSE.md).

Original project: [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs (2022).

Maintained by [Franck Ferman](https://github.com/franckferman).
