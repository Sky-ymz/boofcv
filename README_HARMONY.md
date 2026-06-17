# BoofCV QR CLI — 鸿蒙 PC / aarch64 Linux 构建发布包

## 这是什么

把 BoofCV QR 检测算法用 GraalVM native-image 编成 aarch64 原生可执行文件
（不含 AWT/Swing 依赖），可直接在鸿蒙 PC 上跑，无需 JVM。

**目标产物**：`boofcv_qr_cli_arm64` (~17 MB, aarch64 ELF, musl 全静态)

## 包内目录

```
release_boofcv/
├── README_HARMONY.md          ← 本文件
├── build_aarch64.sh           ← 鸿蒙 PC / aarch64 Linux 上的构建脚本
├── classpath_exploded/        ← BoofCV class 文件 (26 MB, 3868 个 .class)
├── reflect-config.json        ← GraalVM 反射配置 (167 entries)
└── jars/                      ← 第三方依赖 (10 个 jar, ~3 MB)
    ├── ejml-core-0.45.1.jar
    ├── ejml-ddense-0.45.1.jar       ← 关键！缺这个 HDL 会报 NoClassDefFoundError
    ├── ejml-cdense-0.45.1.jar
    ├── ejml-simple-0.45.1.jar
    ├── ejml-fdense-0.45.1.jar
    ├── ejml-zdense-0.45.1.jar
    ├── ejml-dsparse-0.45.1.jar
    ├── ejml-fsparse-0.45.1.jar
    ├── georegression-0.30.0.jar
    └── ddogleg-0.25.1.jar
```

## 快速开始（鸿蒙 PC / aarch64 Linux）

### 1. 安装 GraalVM 21 aarch64 JDK

```bash
# 在你的鸿蒙 PC 或 aarch64 Linux 上
cd ~ && mkdir -p tools && cd tools
wget https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-21.0.2/graalvm-community-jdk-21.0.2_linux-aarch64_bin.tar.gz
tar xzf graalvm-community-jdk-21.0.2_linux-aarch64_bin.tar.gz
export JAVA_HOME=$HOME/tools/graalvm-jdk-21.0.2+13.1
export PATH=$JAVA_HOME/bin:$PATH

# 装 native-image 组件
$JAVA_HOME/bin/gu install native-image
```

### 2. 跑构建脚本

```bash
tar xzf release_boofcv.tar.gz
cd release_boofcv
./build_aarch64.sh
```

预期输出：
```
[INFO] Java: openjdk version "21.0.2" ...
[INFO] Output: boofcv_qr_cli_arm64 (libc=musl)
==================================================================
GraalVM Native Image: Generating 'boofcv_qr_cli_arm64' ...
[1/8] Initializing...
[8/8] Creating native image...         (~2-5 分钟)
==================================================================
[OK] Built boofcv_qr_cli_arm64 (17M)
      ELF 64-bit LSB executable, ARM aarch64, ... statically linked, ...
```

### 3. 跑 QR 检测

```bash
./boofcv_qr_cli_arm64 /path/to/test.pgm /path/to/result.json
cat /path/to/result.json
```

`result.json` 例子（之前在 x86_64 native 跑通的结果）：
```json
{
  "name": "BoofCvCliMin",
  "input": "/path/to/test.pgm",
  "width": 913, "height": 544,
  "duration_ms": 89,
  "detections": [{
    "status": "decoded",
    "message": "http://www.facebook.com/LangersJuice",
    "version": 3, "error": "L", "mask": "M110",
    "corners": [...]
  }]
}
```

## 输入文件要求

**只支持 PGM (P5) 格式灰度图**：

```bash
# 用 ImageMagick 转换（Linux/macOS/WSL 都行）
convert image.jpg -colorspace Gray test.pgm

# 或 python + Pillow
python3 -c "from PIL import Image; Image.open('image.jpg').convert('L').save('test.pgm')"
```

支持的 PGM 子格式：
- P5（binary），maxval 1-65535（自动 rescale 到 8-bit）
- maxval 255 标准 8-bit
- raw RGB 三通道（无 header）——auto-detect

## 鸿蒙签名（如果需要）

鸿蒙 PC 的 ELF 必须经过 OpenHarmony 签名才能在 OS 里执行：

```bash
# 拷贝到能跑鸿蒙 SDK 的 Linux 机器
python3 sign_el2.py \
    --private-key ohos_app_signing.pem \
    --input boofcv_qr_cli_arm64 \
    --output boofcv_qr_cli_arm64_signed.elf
```

OpenHarmony 6.0 的 `sign_el2.py` 在 `openharmony/developtools/hapsigntool/` 下。

签名后 ELF 仍能跑（签名只附加 metadata，不改 binary 内容）。

## 可能踩的坑

### 1. native-image 报 `NoClassDefFoundError: HomographyDirectLinearTransform`

**原因**：`classpath_exploded` 缺 `org/ejml/dense/`。
**解决**：确认 `jars/ejml-ddense-0.45.1.jar` 在 build script classpath 中（默认就在）。

### 2. native-image 报 `Class ... is instantiated reflectively but was never registered`

**原因**：反射未配置。
**解决**：`reflect-config.json` 加 `unsafeAllocated: true` for 缺的那个 class，然后重 build。

### 3. native-image 报 `libc not found` 或链接失败

**原因**：缺 musl libc。
**解决**：
- 鸿蒙 PC：默认 `--libc=musl --static`，需要系统装 musl-gcc 或等价物
- 纯 Linux aarch64：`--libc=glibc`（默认）

切换：`./build_aarch64.sh` 接受 `LIBC_MODE` 环境变量：
```bash
LIBC_MODE=glibc ./build_aarch64.sh    # 动态链接 glibc（更小）
LIBC_MODE=musl ./build_aarch64.sh     # 全静态 musl（推荐，可移植）
```

### 4. 运行报 `Could not initialize class ...`

**原因**：build 时 init 但 run 时重 init 失败。
**解决**：在 `build_aarch64.sh` 加 `--initialize-at-run-time=...`（已有 boofcv 全包）。

### 5. 鸿蒙 PC 找不到 /tmp 或 /dev

**原因**：鸿蒙 PC 文件系统路径不一样。
**解决**：用绝对路径或在 `classpath_exploded` 里加 native binary 路径。

### 6. ELF 被 SELinux / 鸿蒙 Security 模块拦

**原因**：鸿蒙 PC 默认禁止 unsigned/未授权 ELF。
**解决**：必须 `sign_el2.py` 签名 + 在 `app.json5` 里 grant 权限。

## 性能预期

| 指标 | x86_64 native (host) | aarch64 native (鸿蒙 PC 预期) |
|---|---|---|
| 二进制大小 | 17 MB | ~17 MB |
| 启动时间 | <10 ms | <15 ms |
| QR 检测 (913×544) | 89 ms | ~120-200 ms |
| 内存峰值 | ~150 MB | ~180 MB |

## ArkUI 接入（可选）

让 ArkTS 应用调用 native binary：

```typescript
// ArkTS 通过 child_process 启动 binary
import { fileIo } from '@kit.CoreFileKit';

const binPath = '/data/storage/el2/base/files/boofcv_qr_cli_arm64';
const cmd = new ChildProcess();
cmd.exec(`${binPath} ${inputPath} ${outputPath}`);
// 读 result.json 显示给用户
```

或者用 **NDK + JNI** 直接把 native binary 链入应用，效率更高。

## 来源说明

**x86_64 Linux 上验证已通过**（在 WSL Ubuntu 20.04）：

```bash
$ ./boofcv_qr_cli /tmp/qr_test.pgm /tmp/qr_out.json
EXIT: 0
detections=1 duration_ms=89

$ cat /tmp/qr_out.json
{
  "name": "BoofCvCliMin",
  "input": "/tmp/qr_test.pgm",
  "width": 913, "height": 544,
  "duration_ms": 89,
  "detections": [{
    "status": "decoded",
    "message": "http://www.facebook.com/LangersJuice",
    ...
  }]
}
```

aarch64 native binary 尚未在本环境验证（cross-compile 在 GraalVM 21 + qemu
上有未解决的 bug，详见 docs/build_aarch64_log.md）。需要在鸿蒙 PC / aarch64
Linux 上实跑验证。

## 反向联系

如果 aarch64 build 失败，把：
- `build_aarch64.sh` 的完整输出（stdout + stderr）
- `graalvm-ce-builds` 的精确版本
- 鸿蒙 PC 的内核版本（`uname -a`）

发给 Mavis，能快速定位。

---

文件作者: Mavis (2026-06-17)
GraalVM CE: 21.0.2+13.1
BoofCV: 主分支 (commit hash 在 BoofCV-Data submodule 里)