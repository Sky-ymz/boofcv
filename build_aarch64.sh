#!/bin/bash
###############################################################################
# build_aarch64.sh
# 鸿蒙 PC / aarch64 Linux 上把 BoofCV CLI 编成 native binary
# 验证环境：OpenHarmony 6.0 PC + GraalVM CE 21.0.2 aarch64 JDK
###############################################################################
set -euo pipefail

# ----- 配置 -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# GraalVM aarch64 JDK 路径（按你的实际位置改）
export JAVA_HOME="${JAVA_HOME:-$HOME/graalvm-jdk-21.0.2+13.1}"
NATIVE_IMAGE="$JAVA_HOME/bin/native-image"

if [ ! -x "$NATIVE_IMAGE" ]; then
    echo "[ERROR] native-image not found at $NATIVE_IMAGE"
    echo "        Set JAVA_HOME or install native-image:"
    echo "        \$JAVA_HOME/bin/gu install native-image"
    exit 1
fi

OUTPUT_NAME="${OUTPUT_NAME:-boofcv_qr_cli_arm64}"
LIBC_MODE="${LIBC_MODE:-musl}"   # 鸿蒙 PC 用 musl；纯 Linux aarch64 可改 glibc

# ----- 依赖检查 ---------------------------------------------------------------
if [ ! -d classpath_exploded ]; then
    echo "[ERROR] classpath_exploded/ not found in $SCRIPT_DIR"
    exit 1
fi
if [ ! -f reflect-config.json ]; then
    echo "[ERROR] reflect-config.json not found"
    exit 1
fi

JARS=$(ls jars/*.jar 2>/dev/null | tr '\n' ':' | sed 's/:$//')
if [ -z "$JARS" ]; then
    echo "[ERROR] no jars/*.jar found"
    exit 1
fi

# ----- 构建 -------------------------------------------------------------------
echo "[INFO] Java: $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[INFO] Output: $OUTPUT_NAME (libc=$LIBC_MODE)"

"$NATIVE_IMAGE" \
    --no-fallback \
    -H:Name="$OUTPUT_NAME" \
    -H:ReflectionConfigurationFiles=reflect-config.json \
    --initialize-at-run-time=boofcv,georegression,org.ddogleg,org.ejml \
    --libc="$LIBC_MODE" \
    --static \
    -cp "classpath_exploded:${JARS}" \
    boofcv.cli.BoofCvCliMin

# ----- 后处理 -----------------------------------------------------------------
if [ -f "$OUTPUT_NAME" ]; then
    SIZE=$(du -h "$OUTPUT_NAME" | cut -f1)
    FILE_TYPE=$(file "$OUTPUT_NAME")
    echo ""
    echo "============================================================"
    echo "[OK] Built $OUTPUT_NAME ($SIZE)"
    echo "      $FILE_TYPE"
    echo "============================================================"
    echo ""
    echo "Test:"
    echo "  ./$OUTPUT_NAME <input.pgm> <output.json>"
    echo ""
    echo "鸿蒙签名（如果需要）:"
    echo "  python3 sign_el2.py --private-key ohos.pem \\"
    echo "        --input $OUTPUT_NAME --output ${OUTPUT_NAME}_signed.elf"
else
    echo "[ERROR] build failed — $OUTPUT_NAME not produced"
    exit 1
fi