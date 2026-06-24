#!/bin/bash
# Setup OHOS toolchain wrappers
# 关键: OpenJDK 21 要求 CC 报家门 'gcc' (default check)
# 我们用 --version hack 让 clang 自报 gcc
set -uo pipefail

SYSROOT_DIR="$1"
TOOLCHAIN_BIN="$2"
KMP_RESOURCE_DIR="$3"

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "sysroot invalid" >&2
    exit 1
fi

if [ ! -d "$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos" ]; then
    echo "KMP resource dir invalid" >&2
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

SYSROOT_LIB_AARCH64="$SYSROOT_DIR/usr/lib/aarch64-linux-ohos"
KMP_LIBS="$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos"

# 软链 crt 文件
for link_name in crtbegin.o crtbeginS.o crtbeginT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtbegin.o" "$SYSROOT_LIB_AARCH64/$link_name" || true
done
for link_name in crtend.o crtendS.o crtendT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtend.o" "$SYSROOT_LIB_AARCH64/$link_name" || true
done
ln -sf "$KMP_LIBS/libclang_rt.builtins.a" "$SYSROOT_LIB_AARCH64/libclang_rt.builtins.a" || true

# Wrapper: 用 sed 替换 --version 输出, 让 clang 自报 'gcc'
# OpenJDK 21 探测 CC: $CC --version, 期望输出包含 'gcc' (或 'clang' 在新版)
# 用 hack wrapper 让 --version 输出包含 'gcc' 关键字
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << 'WRAPPER_EOF'
#!/bin/bash
# 如果是 --version 调用, 输出伪 gcc 版本
if [ "$1" = "--version" ]; then
    echo "gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
    exit 0
fi
# 否则正常调用 clang
exec /usr/bin/clang-19 --target=aarch64-linux-ohos --sysroot=SYSROOT_PLACEHOLDER --gcc-toolchain=SYSROOT_PLACEHOLDER -fuse-ld=/usr/bin/ld.lld-19 -BSYSROOT_PLACEHOLDER/usr/lib/aarch64-linux-ohos "$@"
WRAPPER_EOF

# 用 sed 替换 SYSROOT_PLACEHOLDER
sed -i "s|SYSROOT_PLACEHOLDER|$SYSROOT_DIR|g" "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

# clang++ wrapper (同样 hack)
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" << 'WRAPPER_EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "g++ version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
    exit 0
fi
exec /usr/bin/clang++-19 --target=aarch64-linux-ohos --sysroot=SYSROOT_PLACEHOLDER --gcc-toolchain=SYSROOT_PLACEHOLDER -fuse-ld=/usr/bin/ld.lld-19 -stdlib=libc++ -BSYSROOT_PLACEHOLDER/usr/lib/aarch64-linux-ohos "$@"
WRAPPER_EOF
sed -i "s|SYSROOT_PLACEHOLDER|$SYSROOT_DIR|g" "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Wrappers:"
cat "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
echo "---"
ls -la "$TOOLCHAIN_BIN/"

echo ""
echo "--- test --version (should report gcc) ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1
echo ""
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" --version | head -1
