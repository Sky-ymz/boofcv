# 已知问题 + 解决方案

## 1. build 报 NoClassDefFoundError: HomographyDirectLinearTransform

**根因**：`classpath_exploded` 缺 `org/ejml/dense/` 路径。`HomographyDirectLinearTransform` 的字段初始化需要 `SolveNullSpaceSvd_DDRM` → `DecompositionFactory_DDRM` → 整个 `ejml-ddense`。

**解决方案**：确认 `build_aarch64.sh` 的 classpath 包含 `jars/ejml-ddense-0.45.1.jar`。

**根因（深层）**：GraalVM 21.0.2 在 native-image 运行时**丢弃 `ExceptionInInitializerError` 的 cause chain**，只显示外层 `NoClassDefFoundError`。所以你看到的错误信息具有误导性——真正的根因是更深层的 ClassNotFoundException。

debug 方法：
```bash
# 用 JVM 跑同一个 main，看到错误信息
$JAVA_HOME/bin/java -cp "classpath_exploded:jars/*" boofcv.cli.HdlTest
# 应输出完整的 NoClassDefFoundError + cause: ClassNotFoundException: org.ejml.dense...
```

## 2. build 报 Class ... is instantiated reflectively but was never registered

**根因**：`boofcv.struct.geo.*` 的 array 类被 `DogArray.init()` 反射分配，但 reflect-config.json 没注册 `unsafeAllocated: true`。

**解决方案**：把缺的 class 加到 `reflect-config.json`：
```json
{ "name": "[Lboofcv.struct.geo.AssociatedPair;", "unsafeAllocated": true }
```

如何找缺哪个 class？看 native-image 错误里提到的 class FQN。

## 3. build 报 libc not found / 链接失败

**根因**：缺 musl libc 或 aarch64 系统库。

**解决方案**：
```bash
sudo apt-get install -y musl-tools gcc-aarch64-linux-gnu zlib1g-dev
# 纯 Linux aarch64 默认有 glibc，可改 LIBC_MODE=glibc
LIBC_MODE=glibc ./build_aarch64.sh
```

## 4. 运行报 Could not initialize class ...

**根因**：build time init 的类，runtime 重新 init 失败。

**解决方案**：`build_aarch64.sh` 里加：
```
--initialize-at-run-time=your.package.name
```

目前对 `boofcv,georegression,org.ddogleg,org.ejml` 都加了，覆盖全。

## 5. 鸿蒙 PC ELF 报 Permission denied

**根因**：未签名或签名证书不对。

**解决方案**：
```bash
# 用正确的证书签名
python3 sign_el2.py --private-key <your-cert.pem> --input boofcv_qr_cli_arm64 --output signed.elf

# 检查签名
python3 sign_el2.py --verify --input signed.elf
```

## 6. 鸿蒙 PC ELF 跑起来但 QR 检测结果为空

**根因 1**：输入图片不是 PGM P5 格式。
**解决方案**：用 ImageMagick 转：
```bash
convert input.jpg -colorspace Gray input.pgm
```

**根因 2**：图片没有 QR code。
**解决方案**：换张有 QR code 的图。

**根因 3**：图片分辨率太低，QR 太远/太小。
**解决方案**：换清晰图。

## 7. aarch64 runner 偶尔 build 失败 (network/timing)

**根因**：GitHub ARM runner 是免费层，可能偶尔 OOM 或超时。

**解决方案**：retry workflow。如果持续失败，加 `-Xmx` 限制：
```yaml
- name: Build
  run: ./build_aarch64.sh
  env:
    JAVA_OPTS: "-Xmx2g"
```

## 8. ELF 在鸿蒙 PC 上跑比预期慢

**根因**：鸿蒙 PC CPU 频率比 x86_64 低；musl 全静态链接有些 syscall 比 glibc 慢。

**预期**：x86_64 native 89ms vs 鸿蒙 PC 120-200ms。如果差太多（>500ms）：
- 检查 CPU governor 是否节能模式
- 用 `-march=armv8.2-a` 重新 build（需要 GraalVM 22+）

## 9. ELF 文件太大 (>50 MB)

**根因**：
- musl 全静态 = 大
- debug symbols 没 strip

**解决方案**：
```bash
$JAVA_HOME/bin/native-image -g              # 关 debug
aarch64-linux-gnu-strip boofcv_qr_cli_arm64  # strip symbols
```

## 10. workflow 触发但卡在 "gu install native-image"

**根因**：GitHub runner 网络问题（GFW 偶尔抽风）。

**解决方案**：retry workflow。如果持续失败，手动 cache：
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.local/share/graalvm
    key: graalvm-cache-v1
```