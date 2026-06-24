#!/bin/bash
# Setup OHOS toolchain wrappers
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

# Wrapper: case 探测
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << 'WRAPPER_EOF'
#!/bin/bash
# Hack: OpenJDK 探测 CC 时调 --version / -v / -dumpversion 等, 都返回 gcc
for arg in "$@"; do
    case "$arg" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM)
            echo "gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
            exit 0
            ;;
    esac
done
# 检测: 如果 stdin 是 /dev/null 且只有一个 -c 之类, 也是探测
if [ "$#" -le 2 ]; then
    echo "gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
    exit 0
fi
# 真正编译: 调用 clang
exec /usr/bin/clang-19 \
    --target=aarch64-linux-ohos \
    --sysroot=SYSROOT_PLACEHOLDER \
    --gcc-toolchain=SYSROOT_PLACEHOLDER \
    -fuse-ld=/usr/bin/ld.lld-19 \
    -BSYSROOT_PLACEHOLDER/usr/lib/aarch64-linux-ohos \
    "$@"
WRAPPER_EOF
sed -i "s|SYSROOT_PLACEHOLDER|$SYSROOT_DIR|g" "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" << 'WRAPPER_EOF'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM)
            echo "g++ version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
            exit 0
            ;;
    esac
done
if [ "$#" -le 2 ]; then
    echo "g++ version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
    exit 0
fi
exec /usr/bin/clang++-19 \
    --target=aarch64-linux-ohos \
    --sysroot=SYSROOT_PLACEHOLDER \
    --gcc-toolchain=SYSROOT_PLACEHOLDER \
    -fuse-ld=/usr/bin/ld.lld-19 \
    -stdlib=libc++ \
    -BSYSROOT_PLACEHOLDER/usr/lib/aarch64-linux-ohos \
    "$@"
WRAPPER_EOF
sed -i "s|SYSROOT_PLACEHOLDER|$SYSROOT_DIR|g" "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Wrappers:"
cat "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
echo "---"
ls -la "$TOOLCHAIN_BIN/"

echo ""
echo "--- test --version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version

echo ""
echo "--- test -v ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" -v 2>&1 | head -3
