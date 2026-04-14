#!/bin/bash
#
# build.sh - Build red-merle .ipk package without the OpenWrt SDK.
#
# An .ipk is an ar archive containing:
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
PKG_VERSION="2.1.0"
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

    # Set executable permissions
    chmod +x "$BUILD_DIR/data/etc/init.d/"*
    chmod +x "$BUILD_DIR/data/etc/gl-switch.d/"*
    chmod +x "$BUILD_DIR/data/usr/bin/"*
    chmod +x "$BUILD_DIR/data/usr/libexec/red-merle"
    chmod +x "$BUILD_DIR/data/lib/red-merle/imei_generate.py"

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

    # Post-install script
    cat > "$BUILD_DIR/control/postinst" << 'EOF'
#!/bin/sh
uci set switch-button.@main[0].func='sim'
uci commit switch-button
/etc/init.d/gl_clients start 2>/dev/null
echo '{"msg": "Successfully installed Red Merle"}' > /dev/ttyS0
EOF
    chmod +x "$BUILD_DIR/control/postinst"

    # Post-remove script
    cat > "$BUILD_DIR/control/postrm" << 'EOF'
#!/bin/sh
uci set switch-button.@main[0].func='tor'
EOF
    chmod +x "$BUILD_DIR/control/postrm"

    # debian-binary
    echo "2.0" > "$BUILD_DIR/debian-binary"

    # Package
    cd "$BUILD_DIR"
    tar czf control.tar.gz -C control .
    tar czf data.tar.gz -C data .
    ar r "../${IPK_FILE}" debian-binary control.tar.gz data.tar.gz 2>/dev/null
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
