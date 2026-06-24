#!/bin/bash
# Setup OHOS toolchain wrappers (dynamic link)
# 关键: 软链 crt 文件到 sysroot
# 注: 不用 set -e, 避免 ls 失败导致脚本整体退出
set -uo pipefail

SYSROOT_DIR="$1"
TOOLCHAIN_BIN="$2"
KMP_RESOURCE_DIR="$3"

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "sysroot invalid: $SYSROOT_DIR" >&2
    exit 1
fi

if [ ! -d "$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos" ]; then
    echo "KMP resource dir invalid: $KMP_RESOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

SYSROOT_LIB_AARCH64="$SYSROOT_DIR/usr/lib/aarch64-linux-ohos"
KMP_LIBS="$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos"

# 软链 crt 文件
for src_name in clang_rt.crtbegin.o clang_rt.crtend.o libclang_rt.builtins.a; do
    if [ -f "$KMP_LIBS/$src_name" ]; then
        # 短名
        ln -sf "$KMP_LIBS/$src_name" "$SYSROOT_LIB_AARCH64/${src_name#clang_rt.}" || true
    fi
done

# 多种可能的变体名都链
for variant in crtbegin.o crtbeginS.o crtbeginT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtbegin.o" "$SYSROOT_LIB_AARCH64/$variant" || true
done
for variant in crtend.o crtendS.o crtendT.o; do
    ln -sf "$KMP_LIBS/clang_rt.crtend.o" "$SYSROOT_LIB_AARCH64/$variant" || true
done

# Wrapper
printf '#!/bin/bash\nexec /usr/bin/clang-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s -fuse-ld=/usr/bin/ld.lld-19 -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

printf '#!/bin/bash\nexec /usr/bin/clang++-19 --target=aarch64-linux-ohos --sysroot=%s --gcc-toolchain=%s -fuse-ld=/usr/bin/ld.lld-19 -stdlib=libc++ -B%s/usr/lib/aarch64-linux-ohos "$@"\n' \
    "$SYSROOT_DIR" "$SYSROOT_DIR" "$SYSROOT_DIR" \
    > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

# 显示结果 (不退出, 即使某些文件不存在)
echo "Wrappers:"
ls -la "$TOOLCHAIN_BIN/" | head -5

echo ""
echo "Sysroot crt files:"
ls -la "$SYSROOT_LIB_AARCH64/crtbegin.o" "$SYSROOT_LIB_AARCH64/crtend.o" "$SYSROOT_LIB_AARCH64/libclang_rt.builtins.a" 2>&1

echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- test compile ---"
printf 'int main() { return 0; }\n' > /tmp/test.c
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos 2>&1
if [ -f /tmp/test_ohos ]; then
    file /tmp/test_ohos
fi
