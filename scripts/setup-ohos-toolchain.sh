#!/bin/bash
# Setup OHOS toolchain wrappers (dynamic link)
set -euo pipefail

SYSROOT_DIR="$1"
TOOLCHAIN_BIN="$2"
KMP_RESOURCE_DIR="$3"

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "sysroot invalid: $SYSROOT_DIR"
    exit 1
fi

if [ ! -d "$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos" ]; then
    echo "KMP resource dir invalid: $KMP_RESOURCE_DIR"
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

# 写 wrapper (一行 exec, 避免续行)
WRAPPER_CLANG="#!/bin/bash
exec /usr/bin/clang-19 --target=aarch64-linux-ohos --sysroot=$SYSROOT_DIR --gcc-toolchain=$SYSROOT_DIR --resource-dir=$KMP_RESOURCE_DIR -fuse-ld=/usr/bin/ld.lld-19 -B$SYSROOT_DIR/usr/lib/aarch64-linux-ohos \"\$@\""

WRAPPER_CLANGPP="#!/bin/bash
exec /usr/bin/clang++-19 --target=aarch64-linux-ohos --sysroot=$SYSROOT_DIR --gcc-toolchain=$SYSROOT_DIR --resource-dir=$KMP_RESOURCE_DIR -fuse-ld=/usr/bin/ld.lld-19 -stdlib=libc++ -B$SYSROOT_DIR/usr/lib/aarch64-linux-ohos \"\$@\""

echo "$WRAPPER_CLANG" > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
echo "$WRAPPER_CLANGPP" > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Wrappers:"
ls -la "$TOOLCHAIN_BIN/"

echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- test compile ---"
echo 'int main() { return 0; }' > /tmp/test.c
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos 2>&1 | head -5
if [ -f /tmp/test_ohos ]; then
    file /tmp/test_ohos
fi
