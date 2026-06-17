# BoofCV QR CLI — OpenHarmony PC aarch64 native binary

把 BoofCV QR 检测算法用 GraalVM native-image 编成 aarch64 原生 binary，
不依赖 JVM，可在鸿蒙 PC 上运行。

## 目录

- `src/` — Java 源码（`BoofCvCliMin` + `PgmPpmReader` + `HdlTest`）
- `classpath_exploded/` — BoofCV 编译后的 class 文件
- `jars/` — 第三方依赖（ejml-*, georegression, ddogleg）
- `reflect-config.json` — GraalVM 反射配置（167 entries）
- `build_aarch64.sh` — 构建脚本（默认 musl 静态）
- `.github/workflows/build-arm64.yml` — GitHub Actions ARM runner workflow
- `docs/` — 详细文档

## 用 GitHub Actions 一键构建

1. **Fork 这个仓库**到你的 GitHub 账号
2. 进入 **Actions** tab → 选择 "build-arm64-native" → **Run workflow**
3. 等 ~5 分钟，下载 artifact `boofcv_qr_cli-arm64-<sha>`
4. 把 binary 传到鸿蒙 PC

## 本地构建（需要 aarch64 Linux）

```bash
# 1. 装 GraalVM CE 21 aarch64
wget https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-21.0.2/graalvm-community-jdk-21.0.2_linux-aarch64_bin.tar.gz
tar xzf graalvm-community-jdk-21.0.2_linux-aarch64_bin.tar.gz -C ~/sdk/
export JAVA_HOME=~/sdk/graalvm-jdk-21.0.2+13.1
export PATH=$JAVA_HOME/bin:$PATH
gu install native-image

# 2. 装 musl 工具链 (Linux only)
sudo apt-get install -y musl-tools gcc-aarch64-linux-gnu zlib1g-dev

# 3. 跑构建
./build_aarch64.sh
# 产出 boofcv_qr_cli_arm64 (~17 MB aarch64 ELF, musl static)
```

## 跑

```bash
./boofcv_qr_cli_arm64 test.pgm result.json
cat result.json
```

只支持 **PGM (P5)** 灰度图。转 jpg → pgm：

```bash
convert image.jpg -colorspace Gray test.pgm
# 或
python3 -c "from PIL import Image; Image.open('image.jpg').convert('L').save('test.pgm')"
```

## 鸿蒙签名

```bash
python3 sign_el2.py --private-key ohos.pem \
    --input boofcv_qr_cli_arm64 --output boofcv_qr_cli_arm64_signed.elf
```

## 详细文档

- [鸿蒙 PC 部署指南](docs/HARMONY.md)
- [已知问题 + 解决方案](docs/KNOWN_ISSUES.md)
- [构建日志参考（WSL x86_64 验证）](docs/BUILD_LOG.md)

## License

待定。BoofCV 本身是 Apache 2.0。

---

文件作者: Mavis
Last updated: 2026-06-17