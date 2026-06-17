# 构建日志参考

## 验证 1：WSL Ubuntu 20.04 x86_64 native build

**环境**：
- GraalVM CE 21.0.2+13.1 (linux-amd64)
- BoofCV 主分支 + ejml-ddense 0.45.1 + georegression 0.30.0 + ddogleg 0.25.1
- musl-gcc 静态链接

**命令**：
```bash
JARS="$(ls jars/*.jar | tr '\n' ':')"
$JAVA_HOME/bin/native-image \
    --no-fallback \
    -H:Name=boofcv_qr_cli \
    -H:ReflectionConfigurationFiles=reflect-config.json \
    --initialize-at-run-time=boofcv,georegression,org.ddogleg,org.ejml \
    --libc=musl \
    --static \
    -cp "classpath_exploded:${JARS}" \
    boofcv.cli.BoofCvCliMin
```

**结果**：
```
[1/8] Initializing...                                                                                    (0.0s @ 0.07GB)
...
[8/8] Creating native image...                                                                          (24.4s @ 2.13GB)
========================================================================================================================
Finished generating 'boofcv_qr_cli' in 26.7s.
```

**二进制信息**：
```
$ file boofcv_qr_cli
boofcv_qr_cli: ELF 64-bit LSB executable, x86-64, version 1 (SYSV),
    static-pie linked, not stripped
$ du -h boofcv_qr_cli
17M     boofcv_qr_cli
```

**运行测试**：
```
$ ./boofcv_qr_cli /tmp/qr_test.pgm /tmp/qr_out.json
EXIT: 0
detections=1 duration_ms=89
```

**result.json**：
```json
{
  "name": "BoofCvCliMin",
  "input": "/tmp/qr_test.pgm",
  "width": 913,
  "height": 544,
  "duration_ms": 89,
  "detections": [
    {"status":"decoded","message":"http://www.facebook.com/LangersJuice",
     "version":3,"error":"L","mask":"M110",
     "corners":[{"x":375.88,"y":156.87},{"x":624.93,"y":91.03},
                {"x":625.70,"y":334.40},{"x":423.55,"y":392.81}]}
  ]
}
```

## 调试历史（重要教训）

### 失败 1：NoClassDefFoundError: HomographyDirectLinearTransform

**症状**：
```
ERROR: Class boofcv.struct.geo.AssociatedPair[] is instantiated reflectively 
       but was never registered
```

**根因（两层）**：
1. `classpath_exploded` 缺 `org/ejml/dense/` (ejml-ddense 没合并)
2. GraalVM 21.0.2 在 native runtime 丢弃 ExceptionInInitializerError 的 cause

**调试方法**：用 JVM 跑同一个 main，看到完整的 cause chain。

### 失败 2：qemu-user-static 下 native-image 无法跑

**症状**：在 qemu-aarch64-static 下跑 `native-image` 时报 "Determining image-builder observable modules failed (Exit status 126)"

**根因**：qemu-user-static 在 aarch64 target 上故意把 `set_robust_list` 返回 ENOSYS（设计选择，从 qemu 2013 至今未改）。glibc 在 robust futex ENOSYS 时会让线程崩溃，导致 native-image 的 image-builder 子进程退出。

**解决方案**：用真正的 aarch64 Linux 机器（GitHub Actions ARM runner 或本地 ARM）。

## 验证 2：GitHub Actions ARM runner (待用户触发)

按 `.github/workflows/build-arm64.yml` 触发 workflow，预计 ~5 分钟出 ARM64 ELF。