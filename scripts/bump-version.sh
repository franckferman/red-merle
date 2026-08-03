#!/bin/sh
#
# bump-version.sh — set the package version everywhere it is user-visible.
#
# One command, one version. The runtime side (SSH banner, GL panel header,
# System Info row) needs nothing here: the postinst hands PKG_VERSION to
# usr/share/red-merle/patch-branding.py, which rewrites those on every install.
#
# Usage: scripts/bump-version.sh 2.5.1
set -eu

cd "$(dirname "$0")/.."

NEW="${1:-}"
case "$NEW" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "Usage: $0 <major.minor.patch>   e.g. $0 2.5.1"; exit 1 ;;
esac

OLD=$(sed -n 's/^PKG_VERSION:=\(.*\)$/\1/p' Makefile)
[ -n "$OLD" ] || { echo "no PKG_VERSION in Makefile"; exit 1; }
echo "$OLD -> $NEW"

sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$NEW/" Makefile
sed -i "s/^PKG_VERSION=\".*\"/PKG_VERSION=\"$NEW\"/" build.sh

# Install snippets in the README and on the website.
for f in README.md docs/index.html; do
    [ -f "$f" ] || continue
    sed -i "s/red-merle_[0-9][0-9.]*_all\.ipk/red-merle_${NEW}_all.ipk/g" "$f"
done

# Website headline.
if [ -f docs/index.html ]; then
    sed -i "s|gl-e750 mudi // v[0-9][0-9.]*|gl-e750 mudi // v${NEW}|g" docs/index.html
fi

echo
tests/check-version.sh
echo
echo "Next: update TODO.md, commit, then tag v$NEW to trigger the release."
