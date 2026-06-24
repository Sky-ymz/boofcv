#!/bin/bash
# 在 OHOS sysroot 上创建 clang wrapper
# 关键：OHOS 默认动态链接，不需要 -static
set -euo pipefail

SYSROOT_DIR="${1:-$(pwd)/sysroot}"
TOOLCHAIN_BIN="${2:-$(pwd)/toolchain/bin}"

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "❌ sysroot 无效: $SYSROOT_DIR"
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

# 写 clang wrapper - 动态链接 OHOS libc
cat > "$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" << WRAPPER_EOF
#!/bin/bash
exec /usr/bin/clang-19 \\
    --target=aarch64-linux-ohos \\
    --sysroot=${SYSROOT_DIR} \\
    --gcc-toolchain=${SYSROOT_DIR} \\
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
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos
file /tmp/test_ohos
echo ""
echo "--- 动态库依赖 ---"
ldd /tmp/test_ohos 2>&1 || echo "(ldd not available, but ELF should be dynamically linked)"
echo ""
echo "--- 测试链接 C++ ---"
cat > /tmp/test.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "Hello from OHOS C++" << std::endl;
    return 0;
}
EOF
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" /tmp/test.cpp -o /tmp/test_cpp
file /tmp/test_cpp
