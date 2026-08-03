#!/bin/sh
#
# check-version.sh — fail when any user-visible version string has drifted.
#
# The package version has one source of truth: PKG_VERSION in the Makefile.
# Everything else (build.sh, the README install snippet, the website) must
# agree with it. Run by CI on every push, so a forgotten spot breaks the build
# instead of shipping a router that proudly announces the wrong release.
#
# Usage: tests/check-version.sh   (from the repository root)
set -eu

cd "$(dirname "$0")/.."

VER=$(sed -n 's/^PKG_VERSION:=\(.*\)$/\1/p' Makefile)
[ -n "$VER" ] || { echo "FAIL: no PKG_VERSION in Makefile"; exit 1; }

fails=0

fail() {
    echo "FAIL: $1"
    fails=$((fails + 1))
}

ok() {
    echo "  ok: $1"
}

echo "Source of truth: Makefile PKG_VERSION = $VER"

# build.sh must match the Makefile — the two build paths ship the same package.
BUILD_VER=$(sed -n 's/^PKG_VERSION="\(.*\)"$/\1/p' build.sh)
if [ "$BUILD_VER" = "$VER" ]; then
    ok "build.sh PKG_VERSION"
else
    fail "build.sh PKG_VERSION is '$BUILD_VER', expected '$VER'"
fi

# Any .ipk filename quoted in the docs must be the current one. Prose like
# "since v2.3.0" is legitimate history and deliberately not checked.
for f in README.md docs/index.html; do
    [ -f "$f" ] || continue
    stale=$(grep -o "red-merle_[0-9][0-9.]*_all\.ipk" "$f" | grep -v "^red-merle_${VER}_all\.ipk$" | sort -u || true)
    if [ -n "$stale" ]; then
        fail "$f references stale package(s): $(echo "$stale" | tr '\n' ' ')"
    else
        ok "$f .ipk filenames"
    fi
done

# The website headline advertises the current release.
if [ -f docs/index.html ]; then
    if grep -q "gl-e750 mudi // v${VER}<" docs/index.html; then
        ok "docs/index.html tagline"
    else
        got=$(grep -o "gl-e750 mudi // v[0-9.]*" docs/index.html | head -1)
        fail "docs/index.html tagline is '${got:-missing}', expected 'gl-e750 mudi // v$VER'"
    fi
fi

# Pool figures quoted in prose drift exactly the way version strings do, and
# did twice: the README advertised 42 prefixes and 18 hotspots long after
# those entries had been removed. Derive the numbers from the code instead of
# trusting the text.
POOL_STATS=$(python3 tests/pool-stats.py)
POOL_TOTAL=$(echo "$POOL_STATS" | cut -d' ' -f1)
POOL_EMEA=$(echo "$POOL_STATS" | cut -d' ' -f2)
POOL_GLOBAL=$(echo "$POOL_STATS" | cut -d' ' -f3)

if grep -q "EMEA bands.*— ${POOL_EMEA} prefixes" README.md; then
    ok "README EMEA pool size ($POOL_EMEA)"
else
    fail "README does not say $POOL_EMEA prefixes for the EMEA pool"
fi
if grep -q "global bands) — ${POOL_GLOBAL} prefixes" README.md; then
    ok "README global pool size ($POOL_GLOBAL)"
else
    fail "README does not say $POOL_GLOBAL prefixes for the global pool"
fi
if grep -q "| ${POOL_TOTAL}, split into per-modem pools" README.md; then
    ok "README total pool size ($POOL_TOTAL)"
else
    fail "README comparison table does not say $POOL_TOTAL unique prefixes"
fi
if [ -f docs/index.html ]; then
    if grep -q "${POOL_EMEA} prefixes per modem variant" docs/index.html; then
        ok "website pool size ($POOL_EMEA)"
    else
        fail "website does not say $POOL_EMEA prefixes per modem variant"
    fi
fi
echo
if [ "$fails" -gt 0 ]; then
    echo "$fails version mismatch(es). Run scripts/bump-version.sh $VER to fix."
    exit 1
fi
echo "All version strings agree on $VER."
