#!/bin/bash
# 在 OHOS sysroot 上创建 clang wrapper
# OHOS NDK 没有 musl 静态库，改为动态链接 + 提供 compiler-rt 内置文件
set -euo pipefail

SYSROOT_DIR="${1:-$(pwd)/sysroot}"
TOOLCHAIN_BIN="${2:-$(pwd)/toolchain/bin}"
CRT_DIR="${3:-$(pwd)/crt}"  # crtbegin.o / crtend.o / libclang_rt.builtins.a

if [ ! -d "$SYSROOT_DIR/usr/include" ]; then
    echo "❌ sysroot 无效: $SYSROOT_DIR"
    exit 1
fi

if [ ! -d "$CRT_DIR" ]; then
    echo "❌ crt 目录不存在: $CRT_DIR"
    echo "   期望: clang_rt.crtbegin.o / clang_rt.crtend.o / libclang_rt.builtins.a"
    exit 1
fi

mkdir -p "$TOOLCHAIN_BIN"

# 复制 crt 文件到 sysroot
CRT_INSTALL_DIR="$SYSROOT_DIR/usr/lib/aarch64-linux-ohos"
cp -f "$CRT_DIR/clang_rt.crtbegin.o" "$CRT_INSTALL_DIR/"
cp -f "$CRT_DIR/clang_rt.crtend.o" "$CRT_INSTALL_DIR/"
cp -f "$CRT_DIR/libclang_rt.builtins.a" "$CRT_INSTALL_DIR/"
echo "Crt files installed:"
ls -la "$CRT_INSTALL_DIR/" | grep -E "clang_rt|crtbegin|crtend"

# 写 clang wrapper
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

echo ""
echo "Wrappers created:"
ls -la "$TOOLCHAIN_BIN/"

# 验证
echo ""
echo "--- clang version ---"
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" --version | head -1

echo ""
echo "--- 测试编译 OHOS 动态链接二进制 ---"
cat > /tmp/test.c << 'EOF'
#include <stdio.h>
int main() {
    printf("Hello from OHOS!\n");
    return 0;
}
EOF
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang" /tmp/test.c -o /tmp/test_ohos
file /tmp/test_ohos
echo ""
echo "--- 测试编译 C++ ---"
cat > /tmp/test.cpp << 'EOF'
#include <iostream>
int main() {
    std::cout << "Hello C++ from OHOS!" << std::endl;
    return 0;
}
EOF
"$TOOLCHAIN_BIN/aarch64-unknown-linux-ohos-clang++" /tmp/test.cpp -o /tmp/test_cpp
file /tmp/test_cpp
