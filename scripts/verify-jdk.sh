#!/bin/bash
# 在鸿蒙 PC 上验证 OHOS-musl OpenJDK 21
# 期望: ./java -version 输出 openjdk version "21.x"
set -euo pipefail

JDK_BIN="${JDK_BIN:-/data/local/tmp/boofcv_test/bin/java}"
JDK_LIB="${JDK_LIB:-/data/local/tmp/boofcv_test/lib}"
JDK_JMODS="${JDK_JMODS:-/data/local/tmp/boofcv_test/jmods}"
JDK_CONF="${JDK_CONF:-/data/local/tmp/boofcv_test/conf}"

if [ ! -x "$JDK_BIN" ]; then
    echo "❌ $JDK_BIN 不存在或不可执行"
    echo "请先把 OHOS-musl JDK push 到鸿蒙 PC:"
    echo "  hdc file send ohos-musl-jdk-21.tar.gz /data/local/tmp/"
    echo "  hdc shell"
    echo "  > cd /data/local/tmp && tar -xzf ohos-musl-jdk-21.tar.gz"
    echo "  > chmod +x /data/local/tmp/boofcv_test/bin/java"
    exit 1
fi

echo "--- java -version ---"
"$JDK_BIN" -version
echo ""

echo "--- file ---"
file "$JDK_BIN"
echo ""

echo "--- ldd ---"
ldd "$JDK_BIN" 2>&1 || echo "(ldd 失败，可能因为不是 Linux 标准二进制——但 ELF 应能被 OHOS 内核加载)"
echo ""

echo "--- 试跑 -XshowSettings ---"
"$JDK_BIN" -XshowSettings:system -version 2>&1 | head -20
echo ""

echo "--- 试跑简单 Java 程序 ---"
TEST_PROG=$(cat <<'JAVA'
public class Test {
    public static void main(String[] args) {
        System.out.println("Hello from OHOS OpenJDK!");
        System.out.println("Property: " + System.getProperty("java.version"));
        System.out.println("OS: " + System.getProperty("os.name"));
        System.out.println("Arch: " + System.getProperty("os.arch"));
    }
}
JAVA
)
echo "$TEST_PROG" > /tmp/Hello.java
javac /tmp/Hello.java 2>/dev/null || /data/local/tmp/boofcv_test/bin/javac /tmp/Hello.java
java -classpath /tmp Hello 2>/dev/null || /data/local/tmp/boofcv_test/bin/java -classpath /tmp Hello
echo ""
echo "=========================================="
echo "✅ 验证完成"
echo "=========================================="
