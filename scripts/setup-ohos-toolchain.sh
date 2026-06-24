#!/bin/bash
# Setup OHOS toolchain wrappers (dynamic link, no --resource-dir)
# 关键: 在 sysroot 内创建 crtbegin/crtend 软链接
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

SYSROOT_LIB_AARCH64="$SYSROOT_DIR/usr/lib/aarch64-linux-ohos"
KMP_LIBS="$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos"

# 软链 crtbegin.o -> clang_rt.crtbegin.o
for link_name in crtbegin.o crtbeginS.o crtbeginT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtbegin.o" "$SYSROOT_LIB_AARCH64/$link_name" 2>/dev/null || true
done

# 软链 crtend.o -> clang_rt.crtend.o
for link_name in crtend.o crtendS.o crtendT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtend.o" "$SYSROOT_LIB_AARCH64/$link_name" 2>/dev/null || true
done

# 软链 libclang_rt.builtins.a
ln -sf "$KMP_LIBS/libclang_rt.builtins.a" "$SYSROOT_LIB_AARCH64/libclang_rt.builtins.a" 2>/dev/null || true

# Wrapper
printf '#!/bin/bash\nexec /usr/bin/clang-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s -fuse-ld=/usr/bin/ld.lld-19 -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

printf '#!/bin/bash\nexec /usr/bin/clang++-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s -fuse-ld=/usr/bin/ld.lld-19 -stdlib=libc++ -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Soft links:"
ls -la "$SYSROOT_LIB_AARCH64/crtbegin*.o" "$SYSROOT_LIB_AARCH64/crtend*.o" "$SYSROOT_LIB_AARCH64/libclang*" 2>&1 | head -10

echo ""
echo "Wrappers:"
ls -la "$TOOLCHAIN_BIN/"

echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- test compile ---"
printf 'int main() { return 0; }\n' > /tmp/test.c
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos 2>&1 | head -10
if [ -f /tmp/test_ohos ]; then
    file /tmp/test_ohos
fi
