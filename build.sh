#!/bin/bash
#
# build.sh - Build red-merle .ipk package without the OpenWrt SDK.
#
# An .ipk is either an ar archive (legacy) or a gzipped tar (modern opkg,
# including the one in GL firmware 4.x) containing:
#   - debian-binary (version string)
#   - control.tar.gz (package metadata)
#   - data.tar.gz (actual files)
#
# Usage:
#   ./build.sh              # build red-merle.ipk
#   ./build.sh clean        # remove build artifacts
#   ./build.sh install      # scp to Mudi and install (requires MUDI_IP env var)

set -e

PKG_NAME="red-merle"
PKG_VERSION="2.19.1"
PKG_ARCH="all"
PKG_DEPENDS="luci-base, gl-sdk4-mcu, coreutils-shred, python3-pyserial"
PKG_MAINTAINER="Franck FERMAN <franckferman@users.noreply.github.com>"
PKG_DESCRIPTION="Anonymity enhancements for GL-E750 Mudi - IMEI randomization, MAC/BSSID randomization, log wiping"

BUILD_DIR="build"
IPK_FILE="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"

clean() {
    rm -rf "$BUILD_DIR" "$IPK_FILE"
    echo "[+] Clean."
}

build() {
    echo "[*] Building ${IPK_FILE}..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/data" "$BUILD_DIR/control"

    # Data: copy all files preserving structure
    cp -a files/* "$BUILD_DIR/data/"
    # never ship python bytecode: it is built for the host interpreter and the
    # router runs a different one
    find "$BUILD_DIR/data" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

    # Set executable permissions
    chmod +x "$BUILD_DIR/data/etc/init.d/"*
    chmod +x "$BUILD_DIR/data/etc/gl-switch.d/"*
    chmod +x "$BUILD_DIR/data/usr/bin/"*
    chmod +x "$BUILD_DIR/data/usr/libexec/red-merle"
    chmod +x "$BUILD_DIR/data/www/cgi-bin/redmerle-api"
    chmod +x "$BUILD_DIR/data/lib/red-merle/imei_generate.py"
    chmod +x "$BUILD_DIR/data/usr/share/red-merle/patch-branding.py"

    # Control file
    cat > "$BUILD_DIR/control/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: ${PKG_ARCH}
Maintainer: ${PKG_MAINTAINER}
Depends: ${PKG_DEPENDS}
Section: utils
Description: ${PKG_DESCRIPTION}
EOF

    # Post-install script.
    # Single-quoted heredoc: no build-time $ expansion (see CLAUDE.md 6.1).
    # The version is a placeholder substituted right after, so nothing in here
    # ever has to be escaped again.
    cat > "$BUILD_DIR/control/postinst" << 'EOF'
#!/bin/sh
uci set switch-button.@main[0].func='sim'
uci commit switch-button
/etc/init.d/red-merle enable 2>/dev/null || true
/etc/init.d/volatile-client-macs enable 2>/dev/null || true
/etc/init.d/gl_clients start 2>/dev/null

# Every GL panel / SSH banner version string comes from this one script, so a
# reinstall refreshes them all instead of leaving stale ones behind.
if [ -f /usr/share/red-merle/patch-branding.py ]; then
    python3 /usr/share/red-merle/patch-branding.py '__PKG_VERSION__' || true
fi

# Activate the /redmerle/ nginx drop-in. If nginx rejects our file, take it
# back out: a bad config here would kill the whole panel at the next restart.
if command -v nginx >/dev/null 2>&1; then
    if ! nginx -t >/dev/null 2>&1; then
        mv /etc/nginx/gl-conf.d/red-merle.conf /tmp/red-merle.conf.rejected 2>/dev/null
        if nginx -t >/dev/null 2>&1; then
            echo "red-merle: nginx rejected the /redmerle/ drop-in, left it out"
        else
            # nginx was already failing before us -> not ours, put it back
            mv /tmp/red-merle.conf.rejected /etc/nginx/gl-conf.d/red-merle.conf 2>/dev/null
        fi
    fi
    # `/etc/init.d/nginx reload` is a no-op on this firmware (the init script
    # ships no reload action), so signal the master process directly.
    if nginx -t >/dev/null 2>&1; then
        if [ -f /var/run/nginx.pid ]; then
            kill -HUP "$(cat /var/run/nginx.pid)" 2>/dev/null || \
                /etc/init.d/nginx restart >/dev/null 2>&1
        else
            /etc/init.d/nginx restart >/dev/null 2>&1
        fi
    fi
fi

# LuCI serves its menu from a cached tree and rpcd only reads ACL files at
# start, so a freshly installed page stays invisible until something happens to
# invalidate them. Drop the cache and reload rpcd, or the Network menu never
# gains its entry.
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1

echo '{"msg": "Successfully installed Red Merle"}' > /dev/ttyS0
EOF
    sed -i "s/__PKG_VERSION__/${PKG_VERSION}/g" "$BUILD_DIR/control/postinst"
    chmod +x "$BUILD_DIR/control/postinst"

    # Config files preserved across upgrades
    cat > "$BUILD_DIR/control/conffiles" << 'EOF'
/etc/config/red-merle
EOF

    # Post-remove script
    cat > "$BUILD_DIR/control/postrm" << 'EOF'
#!/bin/sh
uci set switch-button.@main[0].func='tor'
# opkg parks a copy of the shipped config beside the live one whenever the two
# differ, and owns neither, so it would outlive the package and prove red-merle
# had been installed.
rm -f /etc/config/red-merle-opkg
# our nginx drop-in went away with the package: reload so it stops being served
if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1 && [ -f /var/run/nginx.pid ]; then
    kill -HUP "$(cat /var/run/nginx.pid)" 2>/dev/null || true
fi
exit 0
EOF
    chmod +x "$BUILD_DIR/control/postrm"

    # debian-binary
    echo "2.0" > "$BUILD_DIR/debian-binary"

    # Package (modern tar-format ipk — the ar format is rejected by
    # the opkg shipped in GL firmware 4.x / OpenWrt 22.03)
    cd "$BUILD_DIR"
    tar czf control.tar.gz -C control .
    tar czf data.tar.gz -C data .
    tar czf "../${IPK_FILE}" debian-binary control.tar.gz data.tar.gz
    cd ..

    rm -rf "$BUILD_DIR"

    echo "[+] Built: ${IPK_FILE} ($(du -h "$IPK_FILE" | cut -f1))"
    sha256sum "$IPK_FILE"
}

install_to_mudi() {
    MUDI_IP="${MUDI_IP:-192.168.8.1}"

    if [ ! -f "$IPK_FILE" ]; then
        echo "[!] No .ipk found. Run ./build.sh first."
        exit 1
    fi

    echo "[*] Copying to ${MUDI_IP}..."
    scp "$IPK_FILE" "root@${MUDI_IP}:/tmp/"

    echo "[*] Installing..."
    ssh "root@${MUDI_IP}" "opkg install /tmp/${IPK_FILE} && rm -f /tmp/${IPK_FILE}"

    echo "[+] Installed on ${MUDI_IP}."
}

sdk_build() {
    SDK_URL="https://downloads.openwrt.org/releases/23.05.0/targets/ath79/nand/openwrt-sdk-23.05.0-ath79-nand_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    SDK_FILENAME="openwrt-sdk-23.05.0-ath79-nand_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    SDK_DIR="sdk/${SDK_FILENAME%.tar.xz}"

    echo "[*] Building with OpenWrt SDK (same as CI)..."

    if [ ! -d "sdk" ]; then
        echo "[*] Downloading SDK (~200MB)..."
        mkdir -p sdk
        wget -q --show-progress -P sdk "$SDK_URL"
        echo "[*] Extracting SDK..."
        tar xf "sdk/$SDK_FILENAME" -C sdk
    else
        echo "[*] SDK already downloaded."
    fi

    mkdir -p "$SDK_DIR/package/${PKG_NAME}"
    ln -sf "$(pwd)/Makefile" "$SDK_DIR/package/${PKG_NAME}/"
    ln -sf "$(pwd)/files" "$SDK_DIR/package/${PKG_NAME}/"

    cd "$SDK_DIR"
    scripts/feeds update packages >/dev/null 2>&1
    echo "CONFIG_SIGNED_PACKAGES=n" > .config
    make defconfig >/dev/null 2>&1
    make -j$(nproc) "package/${PKG_NAME}/compile" V=s
    cd ../..

    IPK_PATH=$(find "$SDK_DIR/bin" -name "${PKG_NAME}*.ipk" | head -1)
    if [ -n "$IPK_PATH" ]; then
        cp "$IPK_PATH" .
        echo "[+] Built: $(basename "$IPK_PATH") ($(du -h "$IPK_PATH" | cut -f1))"
        sha256sum "$(basename "$IPK_PATH")"
    else
        echo "[!] Build failed - no .ipk found."
        exit 1
    fi
}

case "${1:-build}" in
    clean)     clean ;;
    build)     build ;;
    sdk-build) sdk_build ;;
    install)   build && install_to_mudi ;;
    *)         echo "Usage: $0 {build|sdk-build|clean|install}"
               echo ""
               echo "  build      Quick local build (no SDK needed)"
               echo "  sdk-build  Build with OpenWrt SDK (same as CI)"
               echo "  clean      Remove build artifacts"
               echo "  install    Build + deploy to Mudi via SSH"
               ;;
esac
