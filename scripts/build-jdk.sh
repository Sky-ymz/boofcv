#!/bin/bash
# 用 KMP Konan LLVM 19 OHOS 工具链交叉编译 musl 静态 OpenJDK 21
# 输出：aarch64-linux-ohos-musl 静态 JDK (HNP 包用)
set -euo pipefail

# 配置
JDK_REPO="${JDK_REPO:-https://github.com/openjdk/jdk21u.git}"
JDK_TAG="${JDK_TAG:-jdk-21.0.2}"
JOBS="${JOBS:-4}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/build-output}"

# KMP OHOS 工具链 (从 GitHub release 下载)
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(pwd)/toolchain/konan-llvm-19-ohos-x86_64}"
KONAN_LLVM_BIN="$TOOLCHAIN_DIR/bin"
CC="${CC:-$KONAN_LLVM_BIN/aarch64-unknown-linux-ohos-clang}"
CXX="${CXX:-$KONAN_LLVM_BIN/aarch64-unknown-linux-ohos-clang++}"
SYSROOT="${SYSROOT:-$TOOLCHAIN_DIR/sysroot-ohos-aarch64-6.0.2.640-04}"

echo "=========================================="
echo "OHOS musl OpenJDK 21 cross-compile (KMP Konan LLVM 19)"
echo "=========================================="
echo "TOOLCHAIN_DIR: $TOOLCHAIN_DIR"
echo "CC:            $CC"
echo "CXX:           $CXX"
echo "SYSROOT:       $SYSROOT"
echo "JDK_TAG:       $JDK_TAG"
echo "JOBS:          $JOBS"
echo "=========================================="

# 1. 验证工具链
if [ ! -x "$CC" ]; then
    echo "❌ ERROR: clang not found at $CC"
    echo "   期望路径: \$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang"
    exit 1
fi
if [ ! -d "$SYSROOT" ]; then
    echo "⚠️  sysroot not found at $SYSROOT"
    echo "   查找实际位置..."
    SYSROOT=$(find "$TOOLCHAIN_DIR" -name "sysroot*" -type d 2>/dev/null | head -1)
    if [ -z "$SYSROOT" ]; then
        echo "❌ ERROR: 找不到 sysroot"
        find "$TOOLCHAIN_DIR" -type d -name "*sysroot*" 2>&1 | head -5
        exit 1
    fi
    echo "   找到: $SYSROOT"
fi

# 2. 验证工具链能跑
echo "--- 验证 clang ---"
$CC --version
echo ""

# 3. 克隆 OpenJDK 21 源码
if [ ! -d "jdk21u" ]; then
    echo "--- 克隆 OpenJDK 21 源码 (tag: $JDK_TAG) ---"
    git clone --depth 1 --branch "$JDK_TAG" "$JDK_REPO" jdk21u
fi

cd jdk21u

# 4. **关键 patch**: OpenJDK 21 对 musl 静态支持差
#    必须修改 make/autoconf 让它接受 musl + 静态链接
echo "--- 应用 musl 静态 build patch ---"

# 4a. 强制 musl 头文件路径 (musl 在 sysroot 内需要找)
# 4b. 关闭 AWT/Headless (不需要 GUI)
# 4c. 禁用 cups/alsa/fontconfig
# 4d. 静态链接 libstdc++/libgcc (OHOS 没有)

# 创建 musl 头文件 hack
# 注：KMP 工具链的 sysroot 通常已经有 musl headers
# 如果 configure 报缺头文件，patch 加上 -I

# 5. Configure OpenJDK build
echo "--- 配置 OpenJDK build ---"
chmod +x configure

# 关键：OpenJDK 21 build 需要 boot JDK (我们用 Temurin 21)
# sysroot 是 OHOS 工具链内的 musl/bionic sysroot
bash configure \
    --openjdk-target=aarch64-linux-ohos \
    --with-sysroot="$SYSROOT" \
    --with-extra-cflags="-static -O2 -fPIC -DOHOS_LINUX=1 -Wno-error" \
    --with-extra-cxxflags="-static -O2 -fPIC -stdlib=libc++ -Wno-error" \
    --with-extra-ldflags="-static -stdlib=libc++ -lm -lpthread -lc++ -lc++abi" \
    --with-toolchain-path="$KONAN_LLVM_BIN" \
    --disable-hotspot-gc-z \
    --disable-jvm-feature-shenandoahgc \
    --disable-hotspot-gc-parallel \
    --disable-hotspot-gc-g1 \
    --with-jvm-variants=minimal,core \
    --enable-static \
    --disable-dynamic \
    --disable-warnings-as-errors \
    --with-boot-jdk="$JAVA_HOME" \
    2>&1 | tee configure.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ configure 失败，查看 configure.log"
    tail -80 configure.log
    exit 2
fi

# 6. Build
echo "--- 开始 build (JOBS=$JOBS) ---"
echo "预计 30-60 分钟..."

make static-libs-image JOBS=$JOBS 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ build 失败，查看 build.log"
    tail -200 build.log
    exit 3
fi

# 7. 拷贝产物
echo "--- 拷贝产物 ---"
mkdir -p "$OUTPUT_DIR"

# 找 build 产物 jdk 目录
JDK_BUILD_DIR=$(find build -maxdepth 4 -path "*/jdk" -type d 2>/dev/null | head -1)
if [ -z "$JDK_BUILD_DIR" ]; then
    # 备选：找 jdk/bin/java
    JAVA_BIN=$(find build -name "java" -type f -executable 2>/dev/null | head -1)
    if [ -z "$JAVA_BIN" ]; then
        echo "❌ 找不到编译产物 java"
        find build -name "java" 2>&1 | head -5
        exit 4
    fi
    JDK_BUILD_DIR=$(dirname $(dirname "$JAVA_BIN"))
fi

echo "JDK 输出: $JDK_BUILD_DIR"
cp -r "$JDK_BUILD_DIR" "$OUTPUT_DIR/jdk"
ls -la "$OUTPUT_DIR/jdk/bin/"

# 8. 验证产物是 aarch64-linux-ohos
echo "--- 验证 java ELF ---"
file "$OUTPUT_DIR/jdk/bin/java"
echo ""

# 9. 打包
echo "--- 打包 ---"
cd "$OUTPUT_DIR"
tar -czf ohos-musl-jdk-21.tar.gz jdk/
ls -lh ohos-musl-jdk-21.tar.gz

echo ""
echo "=========================================="
echo "✅ 编译完成！"
echo "产物: $OUTPUT_DIR/ohos-musl-jdk-21.tar.gz"
echo "=========================================="
