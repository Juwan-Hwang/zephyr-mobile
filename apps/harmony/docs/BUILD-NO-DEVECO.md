# 不用 DevEco Studio 构建 apps/harmony（Linux x86_64 / aarch64）

脚本都在 `apps/harmony/tools/`，不含任何签名材料，大文件（CLT / SDK / JRE / qemu / x86 运行库）由脚本下载到
`$HMOS_TOOLS_DIR`（默认 `~/.cache/zephyr-harmony-tools`，约 10 GB），**不要提交进仓库**。

| 脚本 | 作用 |
|---|---|
| `env.sh` | 公共变量（`HMOS_TOOLS_DIR`、`CLT_VERSION`、`CLT_DIR`、`OH_SDK_DIR`、`JAVA`、`NODE`、`QEMU_X86`、`X86ROOT`），全部可用环境变量覆盖 |
| `fetch-host-deps.sh` | 缺什么装什么到 `$HMOS_TOOLS_DIR`（不需 root）：Java 21 JRE（宿主架构）；非 x86_64 宿主再装 qemu-user + amd64 运行库（libc6 libstdc++6 libgcc-s1 zlib1g libssl3t64 libatomic1 libgl1 libglvnd0 libglx0 libx11-6 libxcb1 libxau6 libxdmcp6 libbsd0 libmd0）。用 Debian trixie 源 + `apt-get download` + `dpkg-deb -x` |
| `fetch-clt.sh [ver]` | HarmonyOS Command Line Tools linux-x64（hvigor + ohpm + HarmonyOS SDK：`sdk/default/{openharmony,hms}`），sha256 校验 |
| `fetch-oh-sdk.sh` | OpenHarmony 6.1-Release 公开 SDK（API 23，仅给快速检查用） |
| `wrap-x86.sh <dir>…` | 非 x86_64 宿主：SDK 里 x86_64 可执行文件就地改名 `*.x86`，原位放 sh 包装 → `qemu-x86_64 -L $X86ROOT`；幂等；`HMOS_X86_LD_PATH` 追加 .so 搜索路径 |
| `build-hmos.sh` | **发布构建**：CLT 自带 hvigor + HarmonyOS SDK，项目原样（runtimeOS HarmonyOS、deviceTypes phone/tablet），默认 `BUILD_MODE=release`；可选签名 |
| `build-ohos-check.sh` | 快速 ArkTS 检查：npm hvigor 6.26.20 + OpenHarmony SDK；副本里改成 OpenHarmony/`default` 设备，产物不能装机 |

## 一次性准备
```sh
cd apps/harmony
tools/fetch-host-deps.sh       # x86_64 宿主若已有 java ≥17 则什么都不做
tools/fetch-clt.sh             # 默认 6.1.1.280（≈2 GB 下载，解压 ≈5 GB）
```

## 发布构建 + 签名
```sh
export ZEPHYR_SIGNING_DIR=/path/to/zephyr-signing/harmony   # 私有仓库克隆，内有 sign-hap.sh；不设则只出未签名 HAP
tools/build-hmos.sh            # 或 --bg 后 --wait（工具命令有超时上限的环境）
CLEAN=1 tools/build-hmos.sh    # 全量
```
- 未签名：`$HMOS_WORK_DIR/proj/entry/build/default/outputs/default/entry-default-unsigned.hap`
  （`HMOS_WORK_DIR` 默认 `$HMOS_TOOLS_DIR/work/hmos`）
- 签名：`$SIGNED_HAP`（默认 `$HMOS_WORK_DIR/zephyr-release-signed.hap`）。`build-hmos.sh` 用
  `JAVA=… SIGN_JAR=<CLT>/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar bash $ZEPHYR_SIGNING_DIR/sign-hap.sh <in> <out>`，
  该脚本做 `sign-app` + `verify-app`。证书 / profile / 口令只在私有仓库 `Juwan-Hwang/zephyr-signing`，绝不放进本仓库。
- 校验产物：`unzip -p <hap> module.json` 里 `app.debug` 应为 `false`、`compileSdkType` 为 `HarmonyOS`、
  `module.deviceTypes` 含 `phone`。
- 云调试（AGC）只收 release 证书 + release profile 签名的包（profile 不带设备列表）。

## CLT 从哪来
官方下载中心（https://developer.huawei.com/consumer/cn/download/）要登录且链接带会话签名，不能直接 curl。公开镜像：

| 版本 | SDK | 来源 | sha256 |
|---|---|---|---|
| 6.1.1.280（默认） | HarmonyOS 6.1.1 Release，API 24（Ohos_sdk_public 6.1.1.125），hvigor 6.24.2 | https://github.com/ErBWs/ohos-sdk/releases/tag/6.1.1.280 （`ohos-sdk-linux-amd64.tar.gz.aa` + `.ab` 拼接） | `3d37eb5a3a81358a9731c35265f4f29d8ecf1028b0bbbb777f2928cd6990aa83`（tar.gz） |
| 6.0.1.251 | HarmonyOS 6.0.1，API 21 —— 低于本项目 compatibleSdkVersion 23，不可用 | https://huggingface.co/csukuangfj/harmonyos-commandline-tools | `e971348eabe959b41b1d07fae037b3cc53ab2c0a8306f0895357dd45f98ad421`（zip） |

更新的 ErBWs release（26.0.0.x，API 26）也可用：在 `fetch-clt.sh` 里加一行版本 + sha256。
镜像是第三方转存，sha256 只保证与镜像一致；能登录下载中心时，用官方页面公布的 sha256 再核一次更稳。
aarch64 原生（box64 包装）的非官方版：https://github.com/SwimmingTiger/third_party_llvm-project/releases（6.1.0.860），未采用。

## aarch64 宿主要点（qemu 跑 x86_64 工具）
- 宿主 node（aarch64）直接跑 CLT 的 `hvigor/bin/hvigorw.js`，`DEVECO_SDK_HOME=<CLT>/sdk`；不用 CLT 自带的 x86_64 node。
- 只包 `openharmony/{toolchains,ets,js}` 与 `hms/{toolchains,ets}`；`native/`（C++ 工具链）本项目不用。
- restool（CompileResource）会 dlopen `hms/toolchains/lib/libimage_transcoder_shared.so`，它要 `liblz4_shared.so`（同目录）、
  `libjsoncpp.so`（`openharmony/previewer/common/bin`）和系统 `libGL.so.1`：前两个靠 `HMOS_X86_LD_PATH`，后者靠 x86root 里的 libgl1 等包。
- `hap-sign-tool.jar` 在 setsid 的后台进程里偶发 JVM SIGSEGV（rc 139），`build-hmos.sh` 会重试一次。
- `ohpm install` 用软链模拟（唯一依赖是本地 `file:` 类型声明包 `libcore_ohos.so`），不访问网络。

## 已知限制
- `entry/libs/<abi>/*.so`（core-ohos / mihomo）不在库里，HAP 不含原生库；应用默认走 MockEngine（演示模式），
  NativeEngine 是动态 import，缺 .so 不影响启动。VPN 实连需要把 .so 放进 `entry/libs/arm64-v8a/` 再构建。
- 安装、运行时、UI 渲染无法在这里验证：用 AGC 云调试或真机。
