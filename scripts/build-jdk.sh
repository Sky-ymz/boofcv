#!/bin/bash
# 简化版：只 echo 关键路径，证明脚本能跑到哪
echo "==== SCRIPT START: $(date) ===="
echo "GITHUB_WORKSPACE=${GITHUB_WORKSPACE:-<NOT SET>}"
echo "PWD=$(pwd)"
echo "LANG=$LANG"
echo "USER=$USER"
echo "HOME=$HOME"
echo "PATH=$PATH"
echo ""

echo "==== CHECK TOOLS ===="
which clang-19 || echo "clang-19 NOT FOUND"
which ld.lld-19 || echo "ld.lld-19 NOT FOUND"
which javac || echo "javac NOT FOUND"
which make || echo "make NOT FOUND"
which autoconf || echo "autoconf NOT FOUND"
echo ""

echo "==== CHECK TOOLCHAIN ===="
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(pwd)/toolchain}"
CC="${CC:-$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang}"
echo "CC=$CC"
ls -la "$CC" 2>&1
echo ""

echo "==== TEST WRAPPER ===="
"$CC" --version 2>&1 | head -3
echo ""

echo "==== GIT CLONE ===="
if [ ! -d "jdk21u" ]; then
    echo "Cloning jdk21u..."
    git clone --depth 1 --branch jdk-21-ga https://github.com/openjdk/jdk21u.git jdk21u 2>&1 | head -10
else
    echo "jdk21u already exists, size: $(du -sh jdk21u 2>&1 | head -1)"
fi
echo ""

echo "==== CD TO jdk21u ===="
cd jdk21u
echo "Now in $(pwd)"
ls -la configure 2>&1
echo ""

echo "==== CONFIGURE ===="
chmod +x configure 2>&1
bash configure \
    --openjdk-target=aarch64-linux-gnu \
    --with-sysroot="${SYSROOT:-$(pwd)/../sysroot}" \
    --with-toolchain-path="$TOOLCHAIN_DIR/bin" \
    --with-extra-cflags="-O2 -fPIC -DOHOS_LINUX=1 -Wno-error" \
    --with-extra-cxxflags="-O2 -fPIC -stdlib=libc++ -Wno-error" \
    --with-extra-ldflags="-stdlib=libc++ -lm -lpthread -lc++ -lc++abi -L${SYSROOT:-$(pwd)/../sysroot}/usr/lib/aarch64-linux-ohos" \
    --disable-jvm-feature-shenandoahgc \
    --with-jvm-variants=core \
    --disable-warnings-as-errors \
    --with-boot-jdk="$JAVA_HOME" \
    2>&1 | tee configure.log | tail -30
echo "configure exit: ${PIPESTATUS[0]}"
echo ""

echo "==== BUILD IMAGES (30 min) ===="
make images JOBS=4 2>&1 | tee build.log | tail -30
echo "build exit: ${PIPESTATUS[0]}"
echo ""

echo "==== FIND OUTPUT ===="
find build -path "*/images/jdk" -type d 2>&1 | head -5
find build -name "java" -type f 2>&1 | head -5
echo ""

echo "==== COPY ===="
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE}/build-output}"
mkdir -p "$OUTPUT_DIR"
JDK_BUILD_DIR=$(find build -maxdepth 4 -path "*/images/jdk" -type d 2>/dev/null | head -1)
if [ -n "$JDK_BUILD_DIR" ]; then
    cp -r "$JDK_BUILD_DIR" "$OUTPUT_DIR/jdk"
    cd "$OUTPUT_DIR"
    tar -czf ohos-jdk-21-dynamic.tar.gz jdk/
    ls -lh ohos-jdk-21-dynamic.tar.gz
    echo "ARTIFACT: $OUTPUT_DIR/ohos-jdk-21-dynamic.tar.gz"
else
    echo "NO jdk/images found, build failed"
fi
echo ""
echo "==== SCRIPT END: $(date) ===="
