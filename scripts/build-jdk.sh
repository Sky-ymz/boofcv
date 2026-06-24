#!/bin/bash
# 用 LLVM 19 + OHOS sysroot 交叉编译 OpenJDK 21 (DYNAMIC LINK)
# OHOS 默认动态链接，所以不用 -static
set -euo pipefail

JDK_REPO="${JDK_REPO:-https://github.com/openjdk/jdk21u.git}"
JDK_TAG="${JDK_TAG:-jdk-21.0.2}"
JOBS="${JOBS:-4}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/build-output}"

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(pwd)/toolchain}"
CC="${CC:-$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang}"
CXX="${CXX:-$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang++}"
SYSROOT="${SYSROOT:-$(pwd)/sysroot}"

echo "=========================================="
echo "OHOS OpenJDK 21 cross-compile (DYNAMIC LINK)"
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
    exit 1
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

# 4. Configure OpenJDK build
# 关键修改：
# - 去掉 -static (OHOS 动态链接)
# - 去掉 -rtlib=compiler-rt (用 OHOS 自带 libgcc)
# - 加 --with-toolchain-path 让 configure 找到 ld.lld-19
echo "--- 配置 OpenJDK build ---"
chmod +x configure

bash configure \
    --openjdk-target=aarch64-linux-ohos \
    --with-sysroot="$SYSROOT" \
    --with-toolchain-path="$TOOLCHAIN_DIR/bin" \
    --with-extra-cflags="-O2 -fPIC -DOHOS_LINUX=1 -Wno-error" \
    --with-extra-cxxflags="-O2 -fPIC -stdlib=libc++ -Wno-error" \
    --with-extra-ldflags="-stdlib=libc++ -lm -lpthread -lc++ -lc++abi -L${SYSROOT}/usr/lib/aarch64-linux-ohos" \
    --disable-hotspot-gc-z \
    --disable-jvm-feature-shenandoahgc \
    --disable-hotspot-gc-parallel \
    --with-jvm-variants=server,core \
    --disable-warnings-as-errors \
    --with-boot-jdk="$JAVA_HOME" \
    2>&1 | tee configure.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ configure 失败，查看 configure.log"
    tail -80 configure.log
    exit 2
fi

# 5. Build
echo "--- 开始 build (JOBS=$JOBS) ---"
echo "预计 30-60 分钟..."

make images JOBS=$JOBS 2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ build 失败，查看 build.log"
    tail -200 build.log
    exit 3
fi

# 6. 拷贝产物
echo "--- 拷贝产物 ---"
mkdir -p "$OUTPUT_DIR"

JDK_BUILD_DIR=$(find build -maxdepth 4 -path "*/images/jdk" -type d 2>/dev/null | head -1)
if [ -z "$JDK_BUILD_DIR" ]; then
    # 备选
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

# 7. 验证产物
echo "--- 验证 java ELF ---"
file "$OUTPUT_DIR/jdk/bin/java"
echo ""

# 8. 打包
echo "--- 打包 ---"
cd "$OUTPUT_DIR"
tar -czf ohos-jdk-21-dynamic.tar.gz jdk/
ls -lh ohos-jdk-21-dynamic.tar.gz

echo ""
echo "=========================================="
echo "✅ 编译完成！"
echo "产物: $OUTPUT_DIR/ohos-jdk-21-dynamic.tar.gz"
echo "=========================================="
