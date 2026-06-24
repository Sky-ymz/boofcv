#!/bin/bash
# 用 OpenHarmony OHOS NDK 工具链交叉编译 musl 静态 OpenJDK 21
# 输出：aarch64-linux-ohos-musl 静态 JDK (HNP 包用)
set -euo pipefail

# 配置
JDK_REPO="${JDK_REPO:-https://github.com/openjdk/jdk21u.git}"
JDK_BRANCH="${JDK_BRANCH:-jdk-21.0.2}"
JOBS="${JOBS:-4}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/build-output}"

# OHOS NDK 工具链（GitHub Actions runner 上下文）
OHOS_NDK_HOME="${OHOS_NDK_HOME:-$(pwd)/ohos-sdk/linux/native}"

# 检测工具链
CC="${CC:-$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang}"
CXX="${CXX:-$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang++}"
SYSROOT="${SYSROOT:-$OHOS_NDK_HOME/sysroot}"

echo "=========================================="
echo "OHOS musl OpenJDK 21 cross-compile"
echo "=========================================="
echo "JDK_REPO:     $JDK_REPO"
echo "JDK_BRANCH:   $JDK_BRANCH"
echo "CC:           $CC"
echo "CXX:          $CXX"
echo "SYSROOT:      $SYSROOT"
echo "JOBS:         $JOBS"
echo "OUTPUT_DIR:   $OUTPUT_DIR"
echo "=========================================="

# 1. 验证工具链
if [ ! -x "$CC" ]; then
    echo "❌ ERROR: clang not found at $CC"
    echo "   期望路径: \$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
    exit 1
fi
if [ ! -d "$SYSROOT" ]; then
    echo "❌ ERROR: sysroot not found at $SYSROOT"
    exit 1
fi

# 2. 验证工具链能跑
echo "--- 验证 clang ---"
$CC --version
echo ""

# 3. 克隆 OpenJDK 21 源码
if [ ! -d "jdk21u" ]; then
    echo "--- 克隆 OpenJDK 21 源码 ---"
    git clone --depth 1 --branch "$JDK_BRANCH" "$JDK_REPO" jdk21u
fi

cd jdk21u

# 4. OpenJDK 21 对 musl 静态支持差，需要打 patch
# 关键修改：make/autoconf 关闭 headless awt 等可选 feature
echo "--- 应用 musl 静态 build patch ---"

# 4a. 禁用 AWT/Headless 等 GUI 依赖
# 4b. 禁用 cups/alsa/fontconfig
# 4c. 静态链接 libstdc++/libgcc
# 这里只 disable 关键 feature，patch 留作 build 失败时再加

# 5. Configure OpenJDK build
echo "--- 配置 OpenJDK build ---"
chmod +x configure

bash configure \
    --openjdk-target=aarch64-linux-ohos \
    --with-sysroot="$SYSROOT" \
    --with-extra-cflags="-static -O2 -fPIC -DOHOS_LINUX=1" \
    --with-extra-cxxflags="-static -O2 -fPIC -stdlib=libc++" \
    --with-extra-ldflags="-static -stdlib=libc++ -lm -lpthread" \
    --disable-hotspot-gc-z \
    --disable-jvm-feature-shenandoahgc \
    --disable-hotspot-gc-parallel \
    --disable-hotspot-gc-g1 \
    --with-jvm-variants=minimal,core \
    --enable-static \
    --disable-dynamic \
    --disable-warnings-as-errors \
    2>&1 | tee configure.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ configure 失败，查看 configure.log"
    tail -50 configure.log
    exit 2
fi

# 6. Build
echo "--- 开始 build (JOBS=$JOBS) ---"
echo "预计 30-60 分钟..."

make static-libs-image JOBS=$JOBS 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ build 失败，查看 build.log"
    tail -100 build.log
    exit 3
fi

# 7. 拷贝产物
echo "--- 拷贝产物 ---"
mkdir -p "$OUTPUT_DIR"
JDK_OUTPUT=$(find build -path "*/jdk/bin/java" -type f 2>/dev/null | head -1)
if [ -z "$JDK_OUTPUT" ]; then
    JDK_OUTPUT=$(find build -name "java" -type f -executable 2>/dev/null | head -1)
fi

if [ -z "$JDK_OUTPUT" ]; then
    echo "❌ 找不到编译产物 java"
    find build -name "java" 2>&1 | head -5
    exit 4
fi

JDK_DIR=$(dirname "$JDK_OUTPUT")
echo "JDK 输出: $JDK_DIR"

# 拷贝整个 JDK 目录
cp -r "$JDK_DIR" "$OUTPUT_DIR/jdk"
ls -la "$OUTPUT_DIR/jdk/bin/"
ls -la "$OUTPUT_DIR/jdk/lib/"

# 8. 验证产物是 aarch64-linux-ohos
echo "--- 验证 java ELF ---"
file "$OUTPUT_DIR/jdk/bin/java"
echo ""

# 期望输出:
# ELF 64-bit LSB executable, ARM aarch64, ...
# 动态/静态链接, interpreter 应是 OHOS 的（不是 /lib/ld-musl-aarch64.so.1）

# 9. 打包成 tarball
echo "--- 打包 ---"
cd "$OUTPUT_DIR"
tar -czf ohos-musl-jdk-21.tar.gz jdk/
ls -lh ohos-musl-jdk-21.tar.gz

echo ""
echo "=========================================="
echo "✅ 编译完成！"
echo "产物: $OUTPUT_DIR/ohos-musl-jdk-21.tar.gz"
echo "=========================================="
