#!/bin/bash
# Setup OHOS toolchain wrappers (dynamic link)
# 直接用 printf -v 写 wrapper (单行 exec)
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

# 用 printf 写单行 wrapper (避免变量展开成多行)
printf '#!/bin/bash\nexec /usr/bin/clang-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s --resource-dir=%s -fuse-ld=/usr/bin/ld.lld-19 -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$KMP_RESOURCE_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

printf '#!/bin/bash\nexec /usr/bin/clang++-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s --resource-dir=%s -fuse-ld=/usr/bin/ld.lld-19 -stdlib=libc++ -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$KMP_RESOURCE_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Wrappers:"
ls -la "$TOOLCHAIN_BIN/"

echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- test compile ---"
printf 'int main() { return 0; }\n' > /tmp/test.c
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos 2>&1 | head -5
if [ -f /tmp/test_ohos ]; then
    file /tmp/test_ohos
fi
