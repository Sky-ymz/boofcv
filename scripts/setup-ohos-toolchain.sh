#!/bin/bash
# 在 OHOS sysroot 上创建 clang wrapper
# 关键：让 Ubuntu clang 19 用 KMP 工具链的 aarch64-ohos resource dir
#       (找 crtbegin/crtend/builtins 等 compiler-rt 文件)
set -euo pipefail

SYSROOT_DIR="${1:-$(pwd)/sysroot}"
TOOLCHAIN_BIN="${2:-$(pwd)/toolchain/bin}"
KMP_RESOURCE_DIR="${3:-$(pwd)/kmp-resource}"

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "❌ sysroot 无效: $SYSROOT_DIR"
    exit 1
fi

if [ ! -d "$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos" ]; then
    echo "❌ KMP resource 目录无效: $KMP_RESOURCE_DIR"
    echo "   期望: \$KMP_RESOURCE_DIR/lib/aarch64-linux-ohos/clang_rt.crtbegin.o"
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

# 写 clang wrapper - 关键是 --resource-dir
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << WRAPPER_EOF
#!/bin/bash
exec /usr/bin/clang-19 \\
    --target=aarch64-linux-ohos \\
    --sysroot=${SYSROOT_DIR} \\
    --gcc-toolchain=${SYSROOT_DIR} \\
    --resource-dir=${KMP_RESOURCE_DIR} \\
    -fuse-ld=/usr/bin/ld.lld-19 \\
    -B${SYSROOT_DIR}/usr/lib/aarch64-linux-ohos \\
    "\$@"
WRAPPER_EOF
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang"

# 写 clang++ wrapper
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" << WRAPPER_EOF
#!/bin/bash
exec /usr/bin/clang++-19 \\
    --target=aarch64-linux-ohos \\
    --sysroot=${SYSROOT_DIR} \\
    --gcc-toolchain=${SYSROOT_DIR} \\
    --resource-dir=${KMP_RESOURCE_DIR} \\
    -fuse-ld=/usr/bin/ld.lld-19 \\
    -stdlib=libc++ \\
    -B${SYSROOT_DIR}/usr/lib/aarch64-linux-ohos \\
    "\$@"
WRAPPER_EOF
chmod +x "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++"

echo "Wrappers created:"
ls -la "$TOOLCHAIN_BIN/"

# 验证
echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- 测试编译 OHOS 动态链接二进制 ---"
echo 'int main() { return 0; }' > /tmp/test.c
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos 2>&1 | head -5
if [ -f /tmp/test_ohos ]; then
    file /tmp/test_ohos
    echo ""
    echo "--- 动态库依赖 ---"
    ldd /tmp/test_ohos 2>&1 || echo "(no ldd)"
else
    echo "❌ 编译失败"
    exit 1
fi
