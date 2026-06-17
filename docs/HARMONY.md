# 鸿蒙 PC 部署指南

## 鸿蒙 PC 限制

- **不能跑 JVM**：GraalVM JDK / native-image 不能在鸿蒙 PC 上执行
- 必须**先在别处构建 aarch64 ELF**，再把 ELF 传到鸿蒙 PC
- ELF 必须经 `sign_el2.py` 签名才能在 OS 里跑

## 三步部署

### 1. 构建 aarch64 ELF（在 GitHub Actions 上）

参见仓库根目录 README.md 的 "用 GitHub Actions 一键构建" 部分。

### 2. 传 ELF 到鸿蒙 PC

```bash
# 假设 ELF 在 ~/Downloads/boofcv_qr_cli_arm64
# 传到鸿蒙 PC（具体方法看你环境：scp / DevEco Studio / U盘 等）
```

### 3. 签名

```bash
# 在鸿蒙 PC 或能跑 sign_el2 的环境上
python3 sign_el2.py \
    --private-key ohos_app_signing.pem \
    --input boofcv_qr_cli_arm64 \
    --output boofcv_qr_cli_arm64_signed.elf
```

签名后的 ELF 仍可执行（签名只附加 metadata，不改 binary 内容）。

## 性能预期

| 指标 | 值 |
|---|---|
| 二进制大小 | ~17 MB |
| 启动时间 | <15 ms |
| QR 检测 (913×544) | ~120-200 ms |
| 内存峰值 | ~180 MB |

## 鸿蒙 PC 文件系统注意

- 不能用 `/tmp/` —— 鸿蒙 PC 文件系统可能不识别
- 用绝对路径：`/data/storage/el2/base/files/test.pgm`
- 输入文件需可读，输出文件需可写

## ArkUI 接入

### 方式 A: child_process

```typescript
import { ChildProcess } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';

const cmd = new ChildProcess();
cmd.exec(`/data/storage/el2/base/files/boofcv_qr_cli_arm64 \
    /data/storage/el2/base/files/test.pgm \
    /data/storage/el2/base/files/result.json`);

// 读 result.json
const file = fileIo.openSync('/data/storage/el2/base/files/result.json',
    fileIo.OpenMode.READ_ONLY);
const stat = fileIo.statSync(file.fd);
const buf = new ArrayBuffer(stat.size);
fileIo.readSync(file.fd, buf);
const text = String.fromCharCode(...new Uint8Array(buf));
const result = JSON.parse(text);
console.log(result.detections[0].message);
```

### 方式 B: NAPI + JNI（效率更高）

把 boofcv 编成 .so，用 NDK 通过 NAPI 暴露给 ArkTS。这条路需要重写 Java 包装为 JNI C 代码，工作量较大。

## 常见错误

### 签名后 ELF 仍报 "Permission denied"

检查 `app.json5` 里 grant 了 `ohos.permission.EXECUTE_NATIVE_BINARY`。

### QR 检测失败无输出

检查输入 PGM 格式是否正确：
```bash
file test.pgm    # 应输出 PGM (P5)
head -c 100 test.pgm | xxd | head
```

### binary 报 "NoClassDefFoundError"（理论上 native binary 不会有，但万一）

回去检查 reflect-config.json 是否漏了类。