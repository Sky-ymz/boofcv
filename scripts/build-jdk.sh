#!/bin/bash
echo "==== SCRIPT START: $(date) ===="

rm -f /tmp/cc-invoke.log /tmp/cxx-invoke.log

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$(pwd)/toolchain}"
CC="${CC:-$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang}"
CXX="${CXX:-$TOOLCHAIN_DIR/bin/aarch64-unknown-linux-ohos-clang++}"
SYSROOT="${SYSROOT:-$(pwd)/sysroot}"
JDK_TAG="${JDK_TAG:-jdk-21-ga}"

echo "==== CHECK TOOLS ===="
which clang-19 || true
which ld.lld-19 || true
which javac || true
which make || true
which autoconf || true

echo ""
echo "==== TEST WRAPPER ===="
"$CC" --version

echo ""
echo "==== GIT CLONE ===="
cd "$TOOLCHAIN_DIR/.."  # cd workspace root
[ ! -d jdk21u ] && git clone --depth 1 --branch "$JDK_TAG" https://github.com/openjdk/jdk21u.git jdk21u 2>&1 | head -3

cd jdk21u
chmod +x configure

echo ""
echo "==== CONFIGURE ===="
bash configure \
    --openjdk-target=aarch64-linux-gnu \
    --with-sysroot="$SYSROOT" \
    --with-toolchain-path="$TOOLCHAIN_DIR/bin" \
    --with-extra-cflags="-O2 -fPIC -DOHOS_LINUX=1 -Wno-error" \
    --with-extra-cxxflags="-O2 -fPIC -stdlib=libc++ -Wno-error" \
    --with-extra-ldflags="-stdlib=libc++ -lm -lpthread -lc++ -lc++abi -L${SYSROOT}/usr/lib/aarch64-linux-ohos" \
    --disable-jvm-feature-shenandoahgc \
    --with-jvm-variants=core \
    --disable-warnings-as-errors \
    --with-boot-jdk="$JAVA_HOME" \
    > configure.log 2>&1

CR=$?
echo "configure exit: $CR"
[ $CR -ne 0 ] && tail -100 configure.log && exit 0

echo ""
echo "==== BUILD ===="
make images JOBS=4 > build.log 2>&1
BR=$?
echo "build exit: $BR"
[ $BR -ne 0 ] && tail -100 build.log && exit 0

echo ""
echo "==== FIND OUTPUT ===="
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE}/build-output}"
mkdir -p "$OUTPUT_DIR"
JDK_BUILD_DIR=$(find build -maxdepth 4 -path "*/images/jdk" -type d 2>/dev/null | head -1)
if [ -n "$JDK_BUILD_DIR" ]; then
    cp -r "$JDK_BUILD_DIR" "$OUTPUT_DIR/jdk"
    cd "$OUTPUT_DIR"
    tar -czf ohos-jdk-21-dynamic.tar.gz jdk/
    ls -lh ohos-jdk-21-dynamic.tar.gz
else
    echo "NO jdk/images found"
fi

echo ""
echo "==== CC INVOKE LOG ===="
[ -f /tmp/cc-invoke.log ] && cat /tmp/cc-invoke.log
[ -f /tmp/cxx-invoke.log ] && cat /tmp/cxx-invoke.log
echo ""
echo "==== SCRIPT END: $(date) ===="

# Always exit 0
exit 0
