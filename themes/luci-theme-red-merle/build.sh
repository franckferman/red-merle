#!/bin/bash
#
# build.sh - Build luci-theme-red-merle .ipk package without the OpenWrt SDK.
#
# An .ipk is an ar archive containing:
#   - debian-binary (version string)
#   - control.tar.gz (package metadata)
#   - data.tar.gz (actual files)
#
# The package ships two LuCI themes:
#   - redmerle        ("Red Merle" dark red theme)
#   - redmerle-hacker (green CRT/phosphor "hacker" theme)
#
# Usage:
#   ./build.sh              # build luci-theme-red-merle_1.0.0_all.ipk
#   ./build.sh clean        # remove build artifacts
#   ./build.sh install      # scp to Mudi and install (requires MUDI_IP env var)

set -e

PKG_NAME="luci-theme-red-merle"
PKG_VERSION="1.0.0"
PKG_ARCH="all"
PKG_DEPENDS="luci-base"
PKG_MAINTAINER="Franck FERMAN <franckferman@users.noreply.github.com>"
PKG_DESCRIPTION="Red Merle LuCI themes: redmerle (dark red) and redmerle-hacker (green CRT phosphor)"

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

    # Permissions: 0755 on uci-defaults scripts, 0644 everywhere else
    chmod 0755 "$BUILD_DIR/data/etc/uci-defaults/"*
    find "$BUILD_DIR/data" -type f ! -path "*/etc/uci-defaults/*" -exec chmod 0644 {} +

    # Control file
    cat > "$BUILD_DIR/control/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: ${PKG_ARCH}
Maintainer: ${PKG_MAINTAINER}
Depends: ${PKG_DEPENDS}
Section: luci
Description: ${PKG_DESCRIPTION}
EOF

    # Post-install script: nothing to do, uci-defaults run automatically
    cat > "$BUILD_DIR/control/postinst" << 'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$BUILD_DIR/control/postinst"

    # debian-binary
    echo "2.0" > "$BUILD_DIR/debian-binary"

    # Package
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

case "${1:-build}" in
    clean)   clean ;;
    build)   build ;;
    install) build && install_to_mudi ;;
    *)       echo "Usage: $0 {build|clean|install}"
             echo ""
             echo "  build    Quick local build (no SDK needed)"
             echo "  clean    Remove build artifacts"
             echo "  install  Build + deploy to Mudi via SSH"
             ;;
esac
