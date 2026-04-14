# red-merle

The *red-merle* software package enhances anonymity and reduces forensic traceability of the **GL-E750 / Mudi 4G mobile wi-fi router ("Mudi router")**. It is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs with additional features and continued maintenance.

*red-merle* addresses the traceability drawbacks of the Mudi router by adding the following features:

1. Mobile Equipment Identity (IMEI) changer (random, deterministic or static)
2. Media Access Control (MAC) address log wiper
3. Basic Service Set Identifier (BSSID) randomization
4. WAN MAC address randomization

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
| BSSID randomization | New random MAC for both WiFi interfaces (2.4 + 5 GHz), defeating WiFi geolocation databases (WiGLE, Google, Apple) |
| WAN MAC randomization | New random MAC for the upstream-facing interface, preventing session correlation across locations |
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

The Mudi router's baseband is a Quectel EP06-E/A Series LTE Cat 6 Mini PCIe module. The IMEI is changed via the AT command `AT+EGMR=1,7,"<IMEI>"` sent over serial (`/dev/ttyUSB3` at 9600 baud).

The IMEI generation process:

1. Select a random prefix from 16 predefined valid TAC prefixes
2. Fill the remaining digits randomly (14 digits total)
3. Compute and append the Luhn checksum digit (15 digits total)
4. Write via AT command

To prevent IMEI leakage during SIM swap, the modem radio is disabled (`AT+CFUN=4`) before the SIM is removed, and a temporary random IMEI is set immediately. The final IMEI is only written after the new SIM is inserted and its IMSI is read.

![Figure 1. The router's radio is turned off and the IMEI is randomized between entries 70 and 80.](./IMEI%20randomization.png)

### BSSID randomization

On each boot, *red-merle* generates a valid unicast MAC address and overrides the current BSSID for both `wlan0` and `wlan1` via OpenWrt UCI commands. WiFi is restarted to apply the change.

### WAN MAC randomization

A random MAC is generated and applied to the upstream WAN interface (`network.@device[1].macaddr`), preventing the Mudi from being tracked by upstream access points across reboots. This may interfere with MAC filtering if enabled on the upstream WiFi AP.

### Client database volatility

The client database at `/etc/oui-tertf` is securely deleted with `shred` on boot, then a `tmpfs` filesystem is mounted at that location. The `gl_clients` service is restarted so it writes to RAM only. Device seizure or flash memory forensics will not recover previously connected client MAC addresses.

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

*red-merle* is a fork of [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs. Key additions:

- **Static IMEI mode** (`-s`): set a specific IMEI, validated with Luhn checksum
- **Deterministic IMEI mode** (`-d`): reproducible IMEI based on IMSI
- **eSIM path handling**: updates `/root/esim/imei` and shreds eSIM logs
- **Quick build script** (`build.sh`): build `.ipk` without the full SDK
- **Toggle rate limiting**: 60-second minimum between switch actions
- **Firmware support**: tested up to firmware 4.3.26

## License

BSD 3-Clause License. See [LICENSE.md](LICENSE.md).

Original project: [blue-merle](https://github.com/srlabs/blue-merle) by SRLabs (2022).

Maintained by [Franck Ferman](https://github.com/franckferman).
