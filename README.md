# red-merle

The *red-merle* software package enhances anonymity and reduces forensic traceability of the **GL-E750 / Mudi 4G mobile wi-fi router ("Mudi router")**. It is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs with additional features and continued maintenance.

*red-merle* addresses the traceability drawbacks of the Mudi router by adding the following features:

1. IMEI changer — random, deterministic (seeded by the SIM's IMSI) or static, from band-aligned TAC pools chosen per modem variant
2. MAC and BSSID randomization at every boot, plus a client database that only ever lives in RAM
3. Log sanitization — syslog, kernel ring buffer, shell history and the GL eSIM daemon log, at boot, at shutdown and after every IMEI change
4. Carrier tracking resistance — SUPL/OMA-DM ports dropped in every mode, and a full AT hardening suite (GNSS, IMS, XTRA, LTE-only) in hardening mode
5. Two operating modes — stealth (invisible to the carrier) and hardening (minimal attack surface) — switchable live, with a revert path for every setting that persists in the modem's NV memory
6. Every behaviour individually switchable through UCI, the CLI or either web interface
7. Three interfaces — an interactive CLI plus `red-merle-ctl`, a LuCI dashboard, and a GL-native dashboard at `/redmerle/` that follows the panel theme

## Threat model

*red-merle*'s protections are layered. Their relevance depends on who you are defending against:

**Carrier-level analytics** (the most common threat for journalists and activists): carriers log which IMEI connects to which cell tower, on which frequency band, at what time. An analyst searching for spoofed IMEIs can filter by:
1. Known blue-merle TAC prefixes (16 fixed values, public on GitHub)
2. Frequency band mismatch between the TAC's expected device and the actual connection
3. Serial number digit patterns (no repeated digits = statistical anomaly)

*red-merle* defeats all three filters: band-aligned TACs, expanded prefix pool (24+ per modem variant), and corrected serial entropy.

**Device seizure** (law enforcement, border crossing, theft): without log wiping, `logread | grep merle` on a seized Mudi reveals the complete IMEI change history with timestamps. *red-merle* wipes system logs at boot, after each IMEI change and at shutdown, so the **trajectory** is gone: whether you changed identity once or fifty times, a seized device shows one snapshot and nothing linking it to the others.

Be clear about what remains. The current IMEI is readable from the modem with a single `AT+GSN` — it lives in NV memory and no host-side measure can hide it. The factory IMEI is printed on the label under the battery and on the box, so anyone physically holding the device can compare the two and see that it has been changed. That reveals *that* spoofing happened, not *which* identities were used. Whether the module also keeps a factory copy in a readable NV item is untested here. And the carrier's own records are of course untouched by anything running on the device.

**Silent carrier geolocation** (intelligence services, lawful interception): carriers can request GPS coordinates from the modem via LPP/SUPL/RRLP without any user-visible indication. *red-merle* disables this at every boot.

**Retrospective network analysis** (the hardest to defend against): an adversary with months of carrier logs can correlate sessions by timing, cell tower patterns, and traffic fingerprints even across IMEI changes. *red-merle* mitigates some of this (DNS flush, MAC randomization) but cannot fully prevent time-based correlation. The standard advice remains: **change your IMEI, change your SIM, and change your location before reconnecting**.

## What this actually buys you

Layered honestly, because the parts of *red-merle* that get the least attention
are the ones that work most reliably.

**Works without caveat.** These defend against device seizure and passive
collection, where there is no adversary model to outsmart — the data is either
recoverable or it is not:

| Protection | Against |
|---|---|
| No identity written to persistent storage, plus log wiping | Seizure: a seized device yields one snapshot, not your trajectory |
| Client MAC database in RAM only | Flash forensics: nothing to recover about who connected |
| MAC and BSSID randomization | WiFi correlation via WiGLE and the Google/Apple location databases |
| SUPL/OMA-DM port blocking | Carrier-initiated positioning, in both modes |
| eSIM daemon IMEI resync | A previous identity sitting in cleartext on flash |
| Corrected serial entropy | Statistical detection: blue-merle produced serials with no repeated digit 100% of the time, which is itself a tell |

**Partial, and worth understanding.** Changing the IMEI defeats the coarse
correlation — same IMEI means same device — which is what the overwhelming
majority of carrier analytics actually does. It does not defeat capability
fingerprinting, which is expensive analysis deployed mainly against bulk SIM-box
fraud rather than run against every subscriber by default.

State the trade plainly: **if** that analysis is run against you, you have traded
*linkable across sessions* for *flagged as anomalous in each session*. That is
usually still the better side of the trade, since an anomaly flag says a device
was modified, not who is holding it — but it is not a free win, and anyone
telling you IMEI spoofing is strictly better is skipping a step.

**Does not help at all.** The carrier's own records, timing and cell-tower
correlation, and anything tied to the SIM: keep the same SIM and your IMSI links
every session regardless of how many IMEIs you burn. This is why the operational
rule is not negotiable — **change the IMEI, change the SIM, change your
location** — and why the local, unglamorous protections above carry more of the
weight than the headline feature does.

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
| iptables blocking (SUPL/OMA-DM ports) | Invisible | Blocks tracking requests |
| MAC randomization | Local only | Prevents WiFi correlation |
| Log sanitization | Device-local | Prevents forensic recovery |
| AT command modifications | **None applied** | Modem features remain active |

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
| All stealth protections | Invisible | Same as stealth |
| GPS/SUPL AT commands | **Highly visible** | Complete modem-level blocking |
| IMS/VoLTE disabling | **Visible** | Prevents metadata collection |
| 4G-only enforcement | **Visible** | Blocks IMSI catcher downgrade attacks |
| Dynamic modem detection | Invisible | Optimized per hardware variant |

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

### Critical decision framework

**The choice between modes cannot be solved universally**. It requires personal risk assessment based on your specific context, adversaries, and acceptable trade-offs.

**Core question**: *Do I gain MORE from protecting against specific documented attack vectors (accepting detectability) or from temporarily blending with normal users (buying time before pattern recognition)?*

**Critical clarification**: "Maximum protection" does NOT mean comprehensive security. Hardening mode only blocks a specific set of known carrier-level tracking methods. It does not protect against:
- Zero-day exploits in modem firmware
- Advanced persistent threats with unknown capabilities  
- Sophisticated correlation attacks using other data sources
- Physical surveillance or device compromise
- Social engineering or operational security failures

The question is really: *"Are the specific GPS/SUPL/IMS protections worth the increased detectability risk in MY situation?"*

#### Stealth mode considerations

**When stealth may be optimal**:
- Mass surveillance is your primary concern
- You want to avoid technical profiling ("person of interest")
- Your adversaries lack sophisticated individual targeting capabilities
- Privacy tool usage itself creates suspicion in your environment
- You're not currently under active investigation

**Stealth mode trade-offs**:
- Gain: **Invisible** to carrier behavioral analysis (initially)
- Gain: **Buys time** by blending with millions of similar profiles
- Gain: **No immediate escalation** of surveillance attention
- Cost: **Temporary protection** - pattern recognition will eventually identify you
- Cost: **Human behavioral patterns** - timing, locations, usage create unique signatures
- Cost: **False security** - "indistinguishable" is temporary, not permanent
- Cost: **Sophisticated correlation** - enough data points will reveal patterns regardless of mode

#### Hardening mode considerations

**When hardening may be optimal**:
- You face technical threats requiring protection against specific GPS/SUPL vectors
- You want to block carrier-initiated positioning requests (but NOT triangulation)
- You've detected active targeting (IMSI catchers, forced downgrades)
- Your technical sophistication is already known/assumed
- Physical safety outweighs operational security concerns

**Hardening mode trade-offs**:
- Gain: **Specific vector protection** - blocks GPS/SUPL/IMS/OMA-DM tracking
- Gain: **Documented attack resistance** - prevents known carrier positioning methods
- Gain: **IMSI catcher mitigation** - 4G-only enforcement
- **Limited scope** - only protects against documented, AT-command-controllable vectors
- Cost: **Highly detectable** signature ("privacy-conscious user")
- Cost: **Population correlation** - linkable with other red-merle users  
- Cost: **Attention escalation** - may trigger enhanced surveillance
- Cost: **False security** - may feel more protected than you actually are

**What hardening does NOT protect against**:
- **Cell tower triangulation** - inherent to cellular network operation, unavoidable
- **Timing-based positioning** - signal timing between towers reveals location
- **Network registration location** - carrier knows which cell towers you connect to
- Modem firmware vulnerabilities or backdoors
- Zero-day exploits in baseband processors
- Advanced correlation using cell tower timing/patterns
- Side-channel attacks through power consumption or RF signatures
- Social engineering, physical surveillance, or device seizure
- Unknown positioning methods not controllable via AT commands

**Critical location reality**: As long as your device connects to cellular networks, your approximate location is known to the carrier through basic network operation. Hardening mode only prevents **additional GPS-precision positioning requests** - it cannot hide that you're connected to specific cell towers.

#### The personal calculation

**Questions to ask yourself**:

1. **Threat sophistication**: Can my adversaries already identify me through other means?
2. **Current exposure**: Do they already know I use privacy tools?
3. **Detection consequences**: What happens if I'm flagged as "technical"?
4. **Protection value**: How much does GPS/SUPL blocking actually help my situation?
5. **Time horizon**: Am I defending against immediate or long-term threats?
6. **Alternative measures**: Do I have other privacy layers (VPN, Tor, burner devices)?

**The signature outlives the identity.** This is the argument that matters most,
and it cuts against the intuition that a targeted person should simply harden and
stay hardened. Hardening leaves a *persistent radio configuration*: IMS off,
LTE-only, no VoLTE, GNSS silent. Rotate the IMEI, swap the SIM, move to another
city — that configuration follows you into every new identity. An analyst who
filters carrier records for "IMS disabled and LTE-only and data-only" gets a very
short list in most regions, and your rotations become a trail through it. The
scarcer the configuration where you are, the worse this gets.

So the useful question is not *who you are*, it is:

1. **Do you rotate identities?** Hardening's signature survives rotation and can
   defeat the very thing red-merle exists to do. This argues for stealth as the
   resting state, whatever your threat level.
2. **Is the specific attack live, here, now?** LTE-only is a real defence against an
   IMSI catcher forcing a 2G/3G downgrade. That is worth its cost while you have
   reason to believe one is operating — not permanently, everywhere.
3. **How rare is the hardened configuration where you are?** Rare means
   identifiable. In a dense LTE market with many data-only devices you blend more
   than you would in a region still leaning on 3G.
4. **What does hardening actually add for you?** Stealth already drops SUPL and
   OMA-DM at the network layer. The delta is modem-level GNSS, IMS metadata, and
   downgrade resistance — narrower than "maximum protection" suggests.

**Not all of hardening is worth the same.** The three things hardening adds are
not equal, and the switch is not all-or-nothing:

| What it adds | What it buys | Signature cost |
|---|---|---|
| **LTE-only** | Blocks the forced downgrade to 2G (no mutual authentication) or 3G that IMSI catchers rely on. A concrete, named attack. | moderate |
| GNSS engine off | Completes the network-layer block: control-plane positioning (LPP over NAS) never reaches iptables, and with the engine off there is no fix to return. | low |
| IMS / VoLTE off | Little here. The Mudi has no voice path, so this only removes IMS registration metadata. | **highest — it is the rarest of the three** |

`lte-only` is already an independent switch, so you do not have to buy the bundle:

```sh
red-merle-ctl hardening off    # stay in stealth
red-merle-ctl lte-only on      # keep downgrade protection
```

That combination gives you the one defence with a named attack behind it, without
the IMS signature that makes a device conspicuous. For most people it is a better
trade than full hardening.

**Treat hardening as an escalation, not a posture.** Raise it when you have a
concrete reason, lower it when the reason passes. "They already know I am a
target" is a poor argument for staying hardened: being known does not stop the
configuration from linking your future identities to your current one.

**Switch dynamically**:
```sh
# Default: invisible protection
red-merle-mode-switch stealth

# Escalate when threats become targeted
red-merle-mode-switch hardening

# Return to stealth when context changes
red-merle-mode-switch stealth
```

Switching to `hardening` applies the AT suite immediately. Switching back to
`stealth` **reverts the persistent modem settings** (LTE-only, IMS, XTRA) —
these are stored in the modem's NV memory and would otherwise survive
reboots. Every command's response is logged in `/tmp/red-merle-at.log`.

> **Connectivity impact of hardening mode** — know before you switch:
>
> | Service | In hardening mode |
> |---------|-------------------|
> | Data (LTE) | Works |
> | **SMS** | Works **via SMS-over-SGs** (standard LTE delivery, used by most carriers — incl. 2FA/bank codes). SMS-over-IMS is disabled with IMS; carriers that deliver SMS *only* over IMS are rare. |
> | Carrier voice calls | Not possible with IMS off and no 2G/3G fallback — but the Mudi is a router with no handset, dialer or audio path, so carrier voice was never available on it in any mode. Not a cost of hardening. |
| VoIP over data (Signal, WhatsApp, SIP) | Works. IMS/VoLTE is the carrier voice stack; internet calls ride the data connection and are unaffected. |
> | First SIM registration | Works — LTE-only restricts *radio technologies*, not network attach. Provisioning SMS arrives via SGs. |
> | Coverage | In areas with **no LTE at all** (3G/2G-only zones), the modem will not connect until you revert. |
>
> **Revert** (restores all radio technologies + IMS immediately):
> ```sh
> red-merle-mode-switch stealth
> ```
> Manual equivalent if ever needed: `gl_modem AT 'AT+QCFG="nwscanmode",0,1'` (EP06) or `gl_modem AT 'AT+QNWPREFCFG="mode_pref",AUTO'` (EM060K), plus `gl_modem AT 'AT+QCFG="ims",1'`.
>
> The GNSS parameters (standalone-only, no NMEA output, SUPL version) are deliberately left hardened — they only affect the modem's own positioning engine, never connectivity.

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

### Honest assessment: No perfect choices

**Both modes involve fundamental trade-offs with no universally correct answer.**

#### Stealth mode reality check

**What it actually provides**:
- Protection against mass automated collection
- Invisibility in bulk carrier analytics  
- Reduced risk of technical profiling

**What it cannot prevent**:
- Sophisticated individual targeting with time and resources
- Advanced correlation techniques by capable adversaries
- Collection via unknown modem vulnerabilities or backdoors
- Eventual detection if you become a high-value target

**The bet you're making**: *"Staying invisible is more valuable than maximum protection because my adversaries primarily use bulk collection methods."*

#### Hardening mode reality check

**What it actually provides**:
- Maximum protection against known attack vectors
- Modem-level blocking of GPS and positioning requests
- Resistance to downgrade attacks and IMSI catchers

**What it cannot prevent**:
- Detection as a "privacy-conscious user" by carrier analysis
- Correlation with other red-merle users through behavioral signatures
- Enhanced surveillance attention due to technical profile
- Collection via attack vectors not addressed by AT commands

**The bet you're making**: *"Maximum protection is worth the increased detectability risk because I face sophisticated technical threats."*

#### The uncomfortable truth

**Neither mode guarantees safety.** Privacy is a process, not a product. Both approaches can fail:

- **Stealth can fail** when adversaries have time, resources, and individual focus
- **Hardening can fail** when being identified as "technical" creates more risk than protection provides
- **Both can fail** against adversaries with capabilities beyond documented protocols

#### Risk acceptance framework

Rather than asking *"Which mode is better?"*, ask:

1. **What am I trying to prevent?** (Mass collection vs targeted attacks vs physical threats)
2. **Who are my adversaries?** (Automated systems vs human analysts vs state actors) 
3. **What are their likely capabilities?** (Bulk analysis vs individual targeting vs advanced techniques)
4. **What happens if I'm detected?** (Inconvenience vs investigation vs physical danger)
5. **What other protections do I have?** (VPN, Tor, burner devices, operational security)
6. **How sophisticated are my likely adversaries?** (Automated systems vs dedicated analysts vs nation-states)
7. **Am I worth the cost of advanced techniques?** (Mass target vs high-value individual)

#### The sophistication spectrum

**Different adversaries have different capabilities and cost thresholds**:

**Mass surveillance systems** (low cost per target):
- Automated carrier analytics and bulk data collection
- Pattern matching against known privacy tool signatures
- **Hardening blocks**: Standard GPS/SUPL requests
- **Hardening doesn't block**: Advanced correlation, unknown collection methods

**Dedicated human analysts** (medium cost per target):
- Individual behavioral analysis and correlation
- Time-intensive investigation of specific targets  
- **Hardening blocks**: Quick technical collection methods
- **Hardening doesn't block**: Patient correlation analysis, alternative data sources

**Advanced persistent threats** (high cost per target):
- Zero-day exploits, custom malware, physical operations
- Sophisticated techniques not in public documentation
- **Hardening blocks**: Basic documented collection vectors
- **Hardening doesn't block**: Custom exploits, advanced persistent access

#### Realistic threat assessment

**Ask yourself honestly**:
- *"Am I interesting enough for them to deploy expensive, sophisticated techniques?"*
- *"Or will they move on to easier targets if basic collection fails?"*
- *"Does blocking GPS/SUPL actually matter if they can correlate my location through cell tower timing?"*

#### The human pattern problem

**Fundamental truth**: You are human, and humans create patterns. No technical solution can eliminate this.

**Inevitable pattern sources**:
- **Temporal**: When you connect, how long sessions last, sleep schedules
- **Geographic**: Where you connect from, travel routes, location clusters  
- **Behavioral**: Data usage patterns, website visits, communication timing
- **Operational**: How you change SIMs, timing of IMEI changes, device reboot patterns

**Both stealth AND hardening modes are vulnerable** to long-term pattern analysis:
- Stealth mode: Patterns emerge through correlation of "normal" behavior
- Hardening mode: Patterns emerge through correlation of technical signatures + behavior

**The goal is buying time, not permanent invisibility**:
- Stealth mode: Delays detection by hiding in normal population noise
- Hardening mode: Reduces specific data collection but creates immediate technical signature

**Minimize patterns where possible**:
- Vary timing, locations, usage patterns
- Use operational security practices
- Change behavior regularly
- But accept that perfect pattern elimination is impossible

**Reality check**: No matter which mode you choose, a sufficiently motivated adversary with enough time and data will eventually identify patterns that reveal your identity. Technology buys time and increases cost for attackers, but cannot solve the fundamental problem that humans have predictable behaviors.

**The decision is ultimately about risk tolerance, time horizons, and realistic threat assessment - not achieving perfect anonymity.**

### Practical guidance

**Default recommendation**: Start with stealth mode for most users, as mass surveillance affects more people than targeted attacks. However, **you must evaluate your own situation**.

**Dynamic approach**: The optimal choice can change based on circumstances:
```sh
# Start with stealth for normal operations
red-merle-mode-switch stealth

# Escalate during high-risk periods
red-merle-mode-switch hardening  

# Return to stealth when context changes
red-merle-mode-switch stealth
```

**Combined with operational security**: Technology alone is insufficient. The most effective privacy strategy layers multiple protections:

- **Technical**: Device hardening (red-merle) + network protection (VPN/Tor)
- **Operational**: Change IMEI + change SIM + change physical location
- **Behavioral**: Vary timing, routes, and communication patterns
- **Compartmental**: Separate devices/identities for different activities

**Final reality check**: Perfect privacy doesn't exist. The goal is raising the cost of surveillance to a level that exceeds the value of targeting you specifically. Both modes contribute to this goal through different mechanisms, and the choice depends on your personal risk assessment.

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

### After a firmware upgrade

A GL firmware upgrade (e.g. 4.3.x → 4.3.26) removes installed packages and reverts firmware-owned files — but **keeps `/etc/config`**, so your red-merle configuration (mode, boot options) survives. Reinstall and everything is re-applied automatically:

```sh
# 1. Make sure the Mudi has internet (repeater / WAN / tethering)
# 2. From your computer:
scp -O red-merle_2.19.1_all.ipk root@192.168.8.1:/tmp/

# 3. On the Mudi — deps, then the package:
opkg update && opkg install coreutils-shred python3-pyserial
opkg install /tmp/red-merle_2.19.1_all.ipk
```

The postinst restores everything: init services, GL panel themes + dropdown entries, SSH banner, header logo and link. If the OpenWrt packages feed is missing (firmware resets it), add it back first:

```sh
echo "src/gz openwrt_packages https://downloads.openwrt.org/releases/22.03.4/packages/mips_24kc/packages" >> /etc/opkg/customfeeds.conf
opkg update
```

Note: GL firmware upgrades may change the admin panel's JS bundle; the dropdown patch applies only if the expected pattern is found (it skips safely otherwise — report it if the Red Merle entries disappear).

## Usage

You may initiate an IMEI update in four different ways:

1. **CLI**: over SSH, either the interactive `red-merle` swap flow or a single `red-merle-ctl imei random`
2. **Toggle**: the Mudi's physical side switch, which runs the two-stage swap
3. **LuCI**: the advanced dashboard at `/cgi-bin/luci/admin/network/red-merle`
4. **GL panel**: the native dashboard at `/redmerle/`, reachable from the RED MERLE sidebar entry

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

### Control utility (`red-merle-ctl`)

A one-stop dashboard and toggle tool, run over SSH. Called without arguments it opens an interactive menu; every action is also available as a subcommand:

```sh
red-merle-ctl                    # interactive menu
red-merle-ctl status             # dashboard: modem, firmware, IMEI, IMSI, own
                                 # number, SIM, registration, signal, network,
                                 # hardening mode, LTE-only & GNSS state, SUPL block
red-merle-ctl lte-only on        # restrict to LTE (downgrade-attack protection)
red-merle-ctl lte-only off       # re-enable all radio technologies
red-merle-ctl gps on|off         # GNSS engine on/off
red-merle-ctl hardening on|off   # apply/revert the full AT suite (same as
                                 # red-merle-mode-switch hardening|stealth)
red-merle-ctl imei show|random|deterministic|set <IMEI>
red-merle-ctl imei native        # claim to be a GL.iNet device (see below)
python3 /lib/red-merle/imei_generate.py -r -t <8-digit TAC>   # pick it yourself
red-merle-ctl imsi               # show IMSI
red-merle-ctl number             # own phone number (AT+CNUM, often empty on data SIMs)
red-merle-ctl signal             # CSQ + serving cell
red-merle-ctl sms list           # list stored SMS
red-merle-ctl sms read 3         # read SMS #3
red-merle-ctl sms send +33612345678 "test from mudi"
red-merle-ctl sms del 3          # delete SMS #3
red-merle-ctl revert             # restore carrier defaults (all RATs, IMS, XTRA)
red-merle-ctl config             # list boot options
red-merle-ctl config randomize_bssid off   # toggle one
red-merle-ctl esim               # eSIM daemon state + cached vs modem IMEI
red-merle-ctl esim off           # stop and disable GL's eSIM LPA daemon
red-merle-ctl esim sync          # resync its cached IMEI to the modem's
red-merle-ctl help               # full usage (also -h / --help)
red-merle-ctl version            # installed package version (also -V / --version)
```

Every command also accepts a `--flag` spelling, so scripts can read either way:

```sh
red-merle-ctl --status
red-merle-ctl --lte-only on
red-merle-ctl --imei random
```

Unknown commands print the usage and exit non-zero, so a typo in a script fails
loudly instead of silently doing nothing.

### Which command is which

| Command | What it is for |
| --- | --- |
| `red-merle` | Interactive **SIM swap**: powers the modem down, sets a new IMEI, waits while you physically swap the SIM card. |
| `red-merle-ctl` | Everything else, day to day: status, toggles, IMEI/IMSI, SMS, boot options. Interactive menu or one-shot commands. |
| `red-merle-mode-switch` | Switches stealth ↔ hardening in one shot. Equivalent to `red-merle-ctl hardening on\|off`. |
| `red-merle-switch-stage1`, `red-merle-switch-stage2` | **Internal.** Driven by the physical side switch through `/etc/gl-switch.d/sim.sh`; not meant to be run by hand. |

### Boot options (UCI)

Every boot behavior is individually switchable — defaults are all `1` (enabled), matching the historical behavior:

| Option | Effect when enabled |
|--------|---------------------|
| `wipe_logs` | Wipe syslog/dmesg/shell history at boot, shutdown and after each IMEI change |
| `randomize_mac` | Randomize upstream + AP MAC addresses at boot |
| `randomize_bssid` | Randomize WiFi BSSIDs at boot |
| `iptables_block` | Block SUPL/OMA-DM carrier-tracking ports (kills IPsec NAT-T) |
| `gps_hardening` | Background AT GPS hardening at boot (hardening mode only) |

Manage them with `red-merle-ctl config` (or `uci get/set red-merle.settings.<option>`); the `status` dashboard shows their current state. Disabled steps are reported as `[OFF]` in the boot OLED summary.

### Panel & UI customization

- **GL-native dashboard**: the `RED MERLE` sidebar entry in the GL admin panel opens `/redmerle/` — a self-contained control page that follows the active panel theme: full status, hardening/LTE-only/GNSS toggles, boot options, random IMEI, AT log. It talks to `/cgi-bin/redmerle-api`, which validates your `Admin-Token` session before touching the modem (403 otherwise).
- **LuCI dashboard**: the advanced UI (Network → Red Merle) offers the same controls plus the SIM swap flow (with Restart modem / Shutdown / Close) — selectable themes `redmerle` / `redmerle-hacker` via the `luci-theme-red-merle` package (System → Language & Style).
- **GL admin panel branding**: matching `Red Merle` / `Red Merle Hacker` panel themes (palette dropdown, top-right), combined GL.iNet + ☢ logo, `Red Merle v<version>` header link (theme-native styling), System Info row, footer credit, and a branded SSH banner.

`lte-only` is the granular flag: it toggles **only** the radio-technology
restriction, independently of the hardening mode. Changes are logged with
their modem responses in `/tmp/red-merle-at.log`.

### Toggle

The side switch drives a two-stage swap. **Which way you slide it decides which
stage runs**, and nothing happens at all if you run them out of order.

| Switch position | What runs |
|---|---|
| **Up** (`on`) | **Stage 1**: kills the radio (`AT+CFUN=4`), sets a throwaway IMEI, then waits. The panel reads *"swap the SIM now, then slide the switch back DOWN"*. |
| **Down** (`off`) | **Stage 2**, but **only if stage 1 ran first** — it checks for `/tmp/red-merle-stage1`. Resets the modem, reads the new IMSI, sets the real IMEI, wipes logs, re-hardens GPS, flushes DNS, then powers the device off. |

So the full sequence is: **switch down at rest → slide up → physically swap the
SIM → slide back down → the device shuts itself off**. The shutdown at the end
is intended, not a crash: you are meant to move before booting again.

Two things worth knowing before you try it:

- **Sliding down without having gone up first does nothing.** The handler only
  runs stage 2 when stage 1 left its marker behind, so a stray flick is safe.
- **Stage 1 refuses to run twice inside 60 seconds** and says so on the panel,
  which is there to stop a bouncing switch from burning two IMEIs.

With no SIM card inserted the flow still completes, but stage 2 will warn that
the IMSI is unreadable and may report the IMEI as unchanged — `AT+EGMR` is
unreliable while the modem is cycling without a card. That is a property of the
modem, not a failure of the swap; run it with a card in.

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

**Choosing the claim yourself: `--tac`.** `imei_generate.py -r -t <8 digits>`
uses exactly the TAC you give it. Offered, not recommended: nothing verifies
that the device it belongs to could report the radio capabilities this modem
does, and an unallocated prefix resolves to nothing at all, which is worse than
not spoofing. Verify your prefix against an allocation database before using it,
and prefer a device in the same class — a portable LTE hotspot rather than a
phone or a fixed router.

**What the default pools contain, and why.** Selection is uniform, so the
composition *is* the policy. Each pool is 42 verified prefixes, roughly evenly
split between portable LTE hotspots and high-volume phones. Hotspots are the
closer match on two axes at once: same device class as the Mudi, and data-only,
so months without a single voice call look normal — which is exactly what a
phone TAC cannot explain. Fixed home routers were excluded on purpose, since a
desk appliance moving between cities is its own anomaly, as were 3G-only devices,
which cannot be camping on LTE at all. Phones are kept in the mix for crowd size
and brand diversity: a pool that was entirely Huawei hotspots would be a pattern
of its own.

**Claiming what you are: `imei native`.** No host-side change can alter the
capability profile the modem reports, so no borrowed TAC will ever match it
exactly. The one claim that stays coherent by construction is your own product
line — a different unit of the same device. `red-merle-ctl imei native` draws
from a GL.iNet TAC, keeping the IMEI unlinked from your previous ones while the
TAC-to-capability relationship remains consistent.

The trade is worse than a small anonymity set, and it is the reason this is not
the default. **The TAC itself becomes the correlator.** Only the serial changes
between generations; the prefix stays `35996594` forever. Two sessions a week
apart both carry it, and an analyst filtering for that prefix in a region finds
every one of them — no capability parsing, no reference database, just a
substring match. It is the same failure this README warns about for hardening
mode: an attribute that survives the rotation it is supposed to enable.

Weigh the two costs, because they are not the same kind:

| Choice | What it costs |
|---|---|
| Rotating TACs from a pool | A **hypothetical** flag: the carrier has to run capability fingerprinting *and* act on the mismatch |
| Fixed native TAC | A **certain** link: filtering by prefix reunites every session, no analysis required |

A certain cost against a hypothetical one is not a close call, which is why the
pools are the default. `native` earns its place only where the device type is
already known or assumed — after a physical inspection, on a network with a
declared fleet — so the link it creates reveals nothing new, while a capability
mismatch would be the louder tell. Outside that narrow case it trades a maybe
for a definitely.

**Verify before trusting any TAC pool, including this one.** A prefix that is
unallocated, or registered to a different device than a comment claims, is worse
than a band mismatch: the carrier's lookup returns nothing, or returns a model
whose radio capabilities cannot possibly produce what the modem reports. Every
prefix shipped here was checked against a public Type Allocation Code database
([~255k allocations](https://github.com/MoazEb/tac-database)), and the model named
in each comment is what that TAC is genuinely registered to. Earlier *red-merle*
releases shipped pools that had never been verified and turned out to be largely
wrong; they were replaced wholesale in 2.12.0. If you fork this, re-verify rather
than inherit the assumption.

**The problem with blue-merle:** blue-merle uses 16 hardcoded TAC prefixes corresponding to consumer phones (Samsung, Apple, etc.) whose LTE band profiles do not match the Mudi's modem. The EP06-E connects on TDD bands B38/B40/B41 that many of those phones do not support. A carrier cross-referencing the IMEI's TAC (which maps to a specific phone model) against the actual bands used for the connection can detect the mismatch.

**Band alignment is regional, and travel can break it.** The pools are built so
the claimed model's band profile is a superset of the bands the Mudi will use —
EMEA bands for the EP06-E, global ones for the EM060K-GL. Roam into a market
using a band your claimed model does not carry (a Europe-oriented TAC on a
US-only band, say) and the coarse mismatch comes back, on a device you chose
precisely to avoid it. If you cross regions regularly, generate a fresh IMEI
after arriving rather than carrying one across the border.

The pools carry both hotspots and phones. A behavioural argument once favoured
hotspots — a device that never places a voice call being unremarkable for a MiFi
and odd for a phone — but it does not survive 2026: carrier voice is a minority
behaviour and data-only plans are common on phones too, so a subscriber who
never places a CS or VoLTE call stands out to no one. See "what the default
pools contain" below for what the weighting actually rests on now.

**How the carrier learns your bands — and why this is not speculation.** The
network does not have to infer anything. During attach it sends a
`UECapabilityEnquiry`, and the modem answers with `UECapabilityInformation`
containing `supportedBandListEUTRA`, the UE category, carrier-aggregation
combinations, MIMO layers and feature group indicators. That is a rich device
fingerprint, transmitted in the clear on the control plane, at every single
attach. The carrier then has two fingerprints to compare: the one expected from
the TAC in your IMEI, and the one your modem actually reported. A mismatch is a
database join, not research.

This is deployed technology, not a hypothetical. It is the basis of commercial
SIM-box fraud detection — see [Oh et al., NDSS 2023](https://www.ndss-symposium.org/wp-content/uploads/2023/02/ndss2023_f416_paper.pdf),
which builds exactly this comparison, and patents such as
[US 12568377](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12568377)
on IMEI verification from control-plane messages.

**What this means for red-merle, stated plainly.** We rewrite the TAC. We cannot
rewrite what the modem reports about itself. On the reference unit the EM060K-GL
advertises 31 LTE bands:

```
1 2 3 4 5 7 8 12 13 14 17 18 19 20 25 26 28 29 30 32 34 38 39 40 41 42 43 46 48 66 71
```

A Galaxy S21 (SM-G991B) advertises 22, and the module reports nine that the phone
does not have at all — including **B14, US public-safety spectrum**. A European
"Galaxy S21" announcing B14 is not a subtle inconsistency.

So be clear about what band-aligned TAC pools buy you. They defeat the **coarse**
filter, the one Issue #1 is about: your claimed model must at least support the
band you are camping on, or you stand out to a trivial query. They do **not**
defeat full capability fingerprinting, and no host-side change can — the
capability report comes from the modem's own firmware.

The roadmap item that helps here is band locking: `AT+QNWPREFCFG="lte_band"`
restricts the bands the module will use, which narrows what it advertises. Even
that is partial, since category, CA combinations and feature groups remain
module-specific. Treat TAC alignment as raising the cost of the cheap query, not
as making the device indistinguishable from the phone it claims to be. Against an
adversary running capability fingerprinting, the defence is not a better TAC —
it is not being worth that level of analysis in the first place.

This is documented in [blue-merle Issue #1](https://github.com/srlabs/blue-merle/issues/1), open since the project's creation. [PR #71](https://github.com/srlabs/blue-merle/pull/71) attempted to fix this by aligning TACs to the EM05-G module's frequency bands, but was closed without being merged. The issue has remained unresolved for over 4 years.

This likely happened because blue-merle originated as a security research proof-of-concept by SRLabs (published alongside an academic paper in 2022). The primary goal was to demonstrate that the Mudi's IMEI could be changed via AT commands, not to build a hardened OPSEC tool. The TAC prefixes were chosen to produce Luhn-valid IMEIs accepted by carriers, without verifying frequency band alignment. Band-level fingerprinting resistance is a concern that arises when defending against a real adversary with carrier-level access, not when writing a conference paper.

**red-merle's approach:** TAC prefixes are curated per modem variant. The function `detect_modem_prefixes()` sends `AT+CGMM` to the modem via serial at startup. The modem responds with its model identifier (e.g. "EP06-E" or "EM060K-GL"), and the script automatically selects the matching TAC list. The user does not need to configure anything.

One annotated pool is maintained, and each entry records the modem variants it
fits, so the two lists below are views over it rather than separate tables. Every
prefix is verified; see the warning above.

- **EP06-E** (Mudi V1, EMEA bands B1/B3/B5/B7/B8/B20/B28/B38/B40/B41) — 24 prefixes:
  - 12 Samsung international variants (Galaxy S21/S22/S23 `SM-…B`, A53 `SM-A536B`)
  - 9 iPhones, international models (13, 14, 15)
  - 3 Xiaomi Redmi Note 11 Pro+ global

- **EM060K-GL** (Mudi V2, global bands) — 24 prefixes:
  Samsung US variants (`SM-…U`) alongside the international ones, iPhone 13/14/15,
  Google Pixel 7/8 and Galaxy S24.

**Band coverage is verified for the phones, not for the hotspots.** The
international Samsung, Apple and Pixel variants carry the full European set
including **B20** (800 MHz, the coverage band for French operators). The Huawei
hotspot entries are a different story: the designations the allocation database
records do not map cleanly onto published spec sheets, and Huawei MiFi regional
variants differ on precisely that band — the E5786s-63a has B1/3/7/8/28/40 and
no B20. So the hotspots are behaviourally ideal and band-unverified at once. If
you are camping on B20 and want the verified side of that trade, use
`red-merle-ctl imei type phone`. Eight further entries that the database listed
only as "HUAWEI MOBILE WIFI", with no model designation at all, were removed:
they could as easily have been 3G-era devices.

Both classes are represented. An earlier version of this section argued that
hotspots deserved the larger share, because a phone that never places a voice
call would stand out. **That argument does not hold in 2026**: carrier voice is a
minority behaviour, OTT messaging replaced it for a large share of subscribers,
and data-only plans are common — including on phones. A subscriber whose device
never places a CS or VoLTE call is unremarkable. Since the phones are also the
entries whose band coverage verifies, there is no longer a reason to weight
against them.

What still holds: fixed home routers are excluded, because a desk appliance that
moves between cities is its own anomaly, and so are 3G-only devices, which cannot
be camping on LTE at all. Brand diversity is kept deliberately — an all-Huawei
pool would be a pattern of its own.

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
blue-merle-toggle: Changed IMEI from 352609114567893 to 354553127891234
blue-merle-toggle: Finished with Stage 2
```

Its `libexec` also logs every action it is asked to perform
(`logger -p notice -t blue-merle-libexec "Libexec $1"`). A device seizure
followed by `logread | grep merle` then reveals the IMEI change history with
timestamps. **blue-merle wipes none of this**: it has no log-wiping code at all,
only the volatile client-MAC database inherited below.

*red-merle* removes every `logger` call and wipes the following:

| Target | How | Backing store |
|---|---|---|
| syslog ring buffer | `/etc/init.d/log restart` | RAM (`log_file` is unset on GL 4.3.26, so syslog never reaches flash) |
| kernel ring buffer | `dmesg -c` | RAM |
| service logs in `/tmp/log/` | `rm -f` | tmpfs |
| shell history: `/root/.ash_history`, `/root/.bash_history`, `/tmp/.ash_history` | `rm -f` | overlay (flash) and tmpfs |
| GL eSIM daemon log `/root/esim/log.txt` | `shred -u` | overlay (flash) |

**When it runs** — every call is gated by the `wipe_logs` UCI option, so turning
it off disables all of them:

- at boot and at shutdown (`/etc/init.d/red-merle` start and stop)
- after an IMEI change from the interactive CLI (`red-merle`)
- at the end of a physical-toggle swap (`red-merle-switch-stage2`)
- at the end of a web SIM swap (`sim-swap finish`)
- before the device powers off from either dashboard (`libexec shutdown`)

**What this does and does not buy you.** The RAM-backed targets — syslog, dmesg,
`/tmp` — are genuinely gone: they never touched flash to begin with. The two
flash-backed targets are a different matter. `/root` and `/etc` sit on an
overlay over **UBIFS**, a copy-on-write filesystem with wear levelling, so
overwriting a path does not overwrite the blocks that held the old content;
`shred` there is best-effort and nothing more. The real mitigation is upstream
of the wipe: red-merle never writes an IMEI, IMSI or ICCID to a persistent file
in the first place. The AT command log lives in `/tmp` for the same reason, and
the IMEI-setting command never passes through it — `imei_generate.py` talks to
the modem directly rather than through the logged `AT_SEND` helper.

Carrier-side records are of course untouched. Local log wiping defends against
device seizure, not against the network operator.

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
│   ├── config/red-merle                         Settings (UCI): mode + behaviour switches
│   ├── gl-switch.d/sim.sh                       Physical toggle handler
│   ├── init.d/
│   │   ├── red-merle                            Boot sequence, shutdown wipe
│   │   └── volatile-client-macs                 Client database kept in RAM
│   └── nginx/gl-conf.d/red-merle.conf           Serves /redmerle/ in the GL panel
├── lib/red-merle/
│   ├── functions.sh                             Shared helpers (AT, wipe, modes, eSIM)
│   └── imei_generate.py                         IMEI generation and modem write
├── usr/
│   ├── bin/
│   │   ├── red-merle                            Interactive SIM swap
│   │   ├── red-merle-ctl                        Control CLI: status, toggles, SMS, eSIM
│   │   ├── red-merle-mode-switch                stealth <-> hardening
│   │   ├── red-merle-switch-stage1|2            Driven by the physical switch (internal)
│   │   └── sim_switch                           Toggle state helper
│   ├── libexec/red-merle                        Backend for both dashboards (13 actions)
│   └── share/
│       ├── luci/menu.d/luci-app-red-merle.json  LuCI menu entry
│       ├── rpcd/acl.d/luci-app-red-merle.json   LuCI permissions
│       └── red-merle/
│           ├── logo.svg                         Combined GL.iNet + trefoil mark
│           └── patch-branding.py                Banner and panel branding, run by postinst
└── www/
    ├── cgi-bin/redmerle-api                     Session-checked bridge for /redmerle/
    ├── luci-static/resources/view/red-merle.js  LuCI dashboard
    ├── redmerle/index.html                      GL-native dashboard
    └── theme/redmerle{,-hacker}/index.css       GL panel themes

scripts/bump-version.sh                          Set the version everywhere at once
tests/check-version.sh                           Fails CI when a version drifts
tests/run-dashboard-tests.sh                     Backend action tests (stubbed modem)
```

## Differences from blue-merle

*red-merle* is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs,
whose last commit dates from June 2025. The fork exists because several
user-reported issues that matter for an anonymity tool have stayed open for years.

### Scope

| | blue-merle | red-merle |
|---|---|---|
| Shipped code | 1,129 lines, 15 files | 3,291 lines, 23 files |
| Shared shell helpers | 9 | 23 |
| Backend actions (libexec) | 6 | 13 |
| Configurable options | none | 9 UCI options |
| TAC prefixes | 16, one list for every device — all verified real and correctly attributed | 39, split into per-modem pools, every one verified against a public allocation database and against published band data |
| Web interface | one LuCI page | LuCI dashboard + GL-native dashboard at `/redmerle/` |
| Control CLI | none | `red-merle-ctl` (status, toggles, SMS, IMEI, eSIM, boot options) |
| Operating modes | one | stealth / hardening, with a revert contract for every persistent AT setting |

### Upstream issues addressed here

| Upstream | Open since | red-merle |
|---|---|---|
| [#1](https://github.com/srlabs/blue-merle/issues/1) Limit frequency bands to those of the spoofed model | Oct 2022 | Partially. TAC pools are split per modem variant and drawn from devices whose band profile covers the Mudi's, which defeats the cheap "does the claimed model even support this band" query. It does not defeat capability fingerprinting — see the section above. [PR #71](https://github.com/srlabs/blue-merle/pull/71) proposed a fix upstream and was closed unmerged; explicit band locking remains on our roadmap. |
| [#82](https://github.com/srlabs/blue-merle/issues/82) Prevent carrier GPS tracking (LPP/SUPL/RRLP) | Feb 2026 | `DISABLE_CARRIER_GPS` sends the AT suite in hardening mode, and SUPL/OMA-DM ports are dropped at the network layer in every mode. |
| [#38](https://github.com/srlabs/blue-merle/issues/38) Add flush DNS | May 2024 | `FLUSH_DNS` restarts dnsmasq after each IMEI change. |
| [#35](https://github.com/srlabs/blue-merle/issues/35) Add toggles to enable/disable options | Apr 2024 | Every boot behaviour is a UCI option, gated inside the shared functions so all call sites honour it, with `red-merle-ctl config` and toggles in both dashboards. |
| [#22](https://github.com/srlabs/blue-merle/issues/22) Instant IMEI change, no questions asked | Dec 2023 | `red-merle-ctl imei random` is a single non-interactive command; both dashboards expose it as one button. |
| [#88](https://github.com/srlabs/blue-merle/issues/88) Released ipk reports the wrong version | Jul 2026 | Not a fix for upstream, but the same class of bug is now structurally impossible here: `tests/check-version.sh` fails CI on any drift and the release workflow refuses a tag that does not match `PKG_VERSION`. |

### Defects fixed in the fork

| Issue | blue-merle | red-merle |
|---|---|---|
| IMEI serial entropy | `random.sample` without replacement: 151,200 combinations (17.2 bits), every serial has all-distinct digits | `random.choices` with replacement: 1,000,000 combinations (19.9 bits) |
| Syslog IMEI leak | `logger "Changed IMEI from X to Y"`, plus the libexec logging every action it runs | All `logger` calls removed |
| Log wiping | None. blue-merle ships no log-wiping code; only the client-MAC database is made volatile | syslog, kernel ring buffer, `/tmp/log`, three shell history files and the GL eSIM daemon log, wiped at boot, at shutdown, after every IMEI change and at the end of both swap flows ([details](#log-sanitization)) |
| IMEI validation | `validate_imei()` checks 14 digits; an IMEI is 15 | Fixed |
| Portability | `[ "$1" == "x" ]` and `[[ ]]` throughout — works only because the stock busybox is built with bash compatibility | POSIX shell everywhere, verified in CI under `dash` |
| Dead code | `luhn.lua` is shipped and called by `GENERATE_IMEI()`, but that function and `SET_IMEI()` are never invoked anywhere in the package — and `lua` is not in its dependency list, so the path would fail outright on a device without it. `SET_IMEI()` also carries the same 14-digit assumption | Removed; IMEI generation goes through Python only |
| eSIM identity leak | Not addressed | GL's eSIM daemon stores the IMEI in `/root/esim/imei` and never refreshes it, so a previous identity persists across reboots. Resynced at the single choke point every IMEI path goes through, and its control channel (TCP 1887) is blocked. |

### Still open upstream, and still open here

Listed for honesty — the fork does not fix everything:
[#15](https://github.com/srlabs/blue-merle/issues/15) ICCID-seeded deterministic IMEI,
[#17](https://github.com/srlabs/blue-merle/issues/17) remove the Python dependency,
[#40](https://github.com/srlabs/blue-merle/issues/40) non-interactive install through LuCI,
[#45](https://github.com/srlabs/blue-merle/issues/45) OUI-based BSSID selection,
[#72](https://github.com/srlabs/blue-merle/issues/72) option to disable the physical toggle,
[#80](https://github.com/srlabs/blue-merle/issues/80) rayhunter integration.
See [TODO.md](TODO.md) for the current roadmap.

## License

*red-merle* is licensed under the **GNU Affero General Public License v3.0** — see
[LICENSE](LICENSE). If you run a modified version of it as a network service, the
AGPL requires you to offer its source to your users.

It forks [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs (2022), which
is BSD 3-Clause. That licence permits relicensing under stronger terms provided the
original notice is preserved, so [LICENSE.md](LICENSE.md) keeps SRLabs' copyright
notice intact. Both files ship together and both apply: BSD-3 to the inherited
work, AGPL-3.0 to this fork.

Maintained by [Franck Ferman](https://github.com/franckferman).
