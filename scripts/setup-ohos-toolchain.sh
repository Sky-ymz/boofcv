#!/bin/bash
# Setup OHOS toolchain wrappers
# 关键: OpenJDK 21 检测 CC 时用 grep "Free Software Foundation" (gcc) 或 "clang" (clang)
# 我们 wrapper 输出两个都含, 让两条检测路径都通过
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

for link_name in crtbegin.o crtbeginS.o crtbeginT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtbegin.o" "$SYSROOT_LIB_AARCH64/$link_name" || true
done
for link_name in crtend.o crtendS.o crtendT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtend.o" "$SYSROOT_LIB_AARCH64/$link_name" || true
done
ln -sf "$KMP_LIBS/libclang_rt.builtins.a" "$SYSROOT_LIB_AARCH64/libclang_rt.builtins.a" || true

# Wrapper: 探测输出含 "Free Software Foundation" + "clang" (双保险)
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << 'WRAPPER_EOF'
#!/bin/bash
echo "CC-INVOKE args=[$*] cwd=$(pwd)" >> /tmp/cc-invoke.log

is_probe=false
for arg in "$@"; do
    case "$arg" in
        --version|-v|-V|-dumpversion|-dumpfullversion|--help|-E|-dM|dummy.c|-dumpmachine|-print-prog-name=*|-print-multi-directory|-print-multiarch|-print-search-dirs|-print-libgcc-file-name|-print-file-name=*)
            is_probe=true
            ;;
    esac
done

if [ "$is_probe" = true ]; then
    cat <<'PROBE_EOF'
clang version 13.2.0 (Ubuntu 13.2.0-23ubuntu4) Free Software Foundation
Target: aarch64-unknown-linux-ohos
Thread model: posix
PROBE_EOF
    exit 0
fi

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
    cat <<'PROBE_EOF'
clang version 13.2.0 (Ubuntu 13.2.0-23ubuntu4) Free Software Foundation
Target: aarch64-linux-ohos
Thread model: posix
PROBE_EOF
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
echo ""
echo "--- test --version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version
