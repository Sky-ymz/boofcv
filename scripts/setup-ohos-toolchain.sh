#!/bin/bash
# Setup OHOS toolchain wrappers
# 关键: OpenJDK 探测 CC 时调 -E /tmp/dummy.c (预处理测试)
# 我们也拦截 -E 探测返回 gcc
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

# Wrapper: 拦截所有探测调用 (探测特征: 1-3 args 或 args 含 -E 或 file dummy.c)
# 真编译: -c/-S/... + 真实文件
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << 'WRAPPER_EOF'
#!/bin/bash
# Log all calls
echo "CC-INVOKE args=[$*] cwd=$(pwd)" >> /tmp/cc-invoke.log

# 判断是不是探测调用
is_probe=false
# 探测特征 1: 1-3 个 args 且包含 -E/-v/-V/-dumpversion/--version
# 探测特征 2: 任何 dummy.c / -dumpmachine / -print-prog-name 等
for arg in "$@"; do
    case "$arg" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM|dummy.c|-dumpmachine|-print-prog-name=*|-print-multi-directory|-print-multiarch|-print-search-dirs|-print-libgcc-file-name|-print-file-name=*)
            is_probe=true
            ;;
    esac
done

# 探测: 返回 gcc
if [ "$is_probe" = true ]; then
    echo "gcc version 13.2.0 (Ubuntu 13.2.0-23ubuntu4)"
    exit 0
fi

# 真编译: 调用 clang
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

is_probe=false
for arg in "$@"; do
    case "$arg" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM|dummy.c|-dumpmachine|-print-prog-name=*|-print-multi-directory|-print-multiarch|-print-search-dirs|-print-libgcc-file-name|-print-file-name=*)
            is_probe=true
            ;;
    esac
done

if [ "$is_probe" = true ]; then
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
ls -la "$TOOLCHAIN_BIN/"
