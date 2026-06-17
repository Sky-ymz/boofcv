#!/bin/bash
# Download gcc-aarch64-linux-gnu and all its transitive deps as .deb files.
# Run this on x86_64 GitHub Actions host (fast native apt).
# Output: a single aarch64-gcc-debs.tar.gz ready to COPY into build context.
set -euo pipefail

OUT="${1:-aarch64-gcc-debs.tar.gz}"
TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT

mkdir -p "$TMP/debs"
cd "$TMP"

# Get list of recursive deps
echo "[1/3] Computing dependency tree..."
DEPS=$(apt-get install -s gcc-aarch64-linux-gnu g++-aarch64-linux-gnu 2>/dev/null \
    | grep -E '^Inst ' | awk '{print $2}')

echo "Packages to download: $(echo "$DEPS" | wc -l)"
echo "$DEPS" | head -20

echo "[2/3] Downloading .deb files..."
for pkg in $DEPS; do
    apt-get download "$pkg" 2>&1 | grep -v '^$' || true
done

ls -lh *.deb | head -5
echo "Total .deb size:"
du -ch *.deb | tail -1

echo "[3/3] Packing $OUT..."
tar czf "$OLDPWD/$OUT" *.deb
ls -lh "$OLDPWD/$OUT"
echo "DONE"