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

# Wrapper: 拦截探测 + log 所有调用
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << 'WRAPPER_EOF'
#!/bin/bash
# Log all invocations to debug OpenJDK probing
echo "CC-INVOKE args=[$*] cwd=$(pwd)" >> /tmp/cc-invoke.log

# 探测: 任何短调用 (1-3 args) 都返回 gcc (OpenJDK 探测)
if [ "$#" -le 3 ]; then
    case "$1" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM)
            echo "gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
            exit 0
            ;;
    esac
fi
# 真正编译
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
echo "CXX-INVOKE args=[$*] cwd=$(pwd)" >> /tmp/cxx-invoke.log

if [ "$#" -le 3 ]; then
    case "$1" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM)
            echo "g++ version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
            exit 0
            ;;
    esac
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
ls -la "$TOOLCHAIN_BIN/"
