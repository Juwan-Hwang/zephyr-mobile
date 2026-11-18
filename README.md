# Zephyr Mobile（iOS & Android）

Zephyr 的移动端：原生 SwiftUI（iOS 17+）与 Jetpack Compose（Android 9+ / minSdk 28）两个 App，共用一个 Rust 核心（UniFFI 绑定）和一个以库形式嵌入的 mihomo（Go）。桌面版 Zephyr 以只读子模块 `vendor/zephyr` 引用，本仓库不改它。

- 协作约定、目录归属、分支与提交规则：[COORDINATION.md](COORDINATION.md)（看板 [#1](https://github.com/Juwan-Hwang/zephyr-mobile/issues/1)）
- 设计依据：[design/notes/mobile-design-spec.md](design/notes/mobile-design-spec.md)、[design/notes/scale-architecture.md](design/notes/scale-architecture.md)、原型 [design/prototype/](design/prototype/)（视觉以原型为准）
- 引擎接口契约：[contract/zephyr-engine.md](contract/zephyr-engine.md)
- 文档：[docs/](docs/)（性能基线 `perf.md`、桌面复用记录 `desktop-reuse.md`、审计报告 `audit/`）

## 目录结构

```
zephyr-mobile/
├── apps/
│   ├── ios/            iOS App（XcodeGen：project.yml → Zephyr.xcodeproj，不入库）
│   │                   App / PacketTunnel（NEPacketTunnelProvider）/ Widgets / Shared
│   │                   Packages/ZephyrKit（引擎协议、MockEngine、Z* 组件、全部页面）
│   │                   说明见 apps/ios/README.md、apps/ios/ARCHITECTURE.md
│   └── android/        Android App（Gradle）：:app（页面、VpnService、磁贴、Glance 小组件）
│                       :core-engine（ZephyrEngine + MockEngine + CoreEngine）、:design（Z* 组件）
├── core-mobile/        Rust crate zephyr-mobile-core：节点索引/搜索、规则测试、场景、订阅差异、运行时配置等；
│                       依赖子模块里的桌面 zephyr-core。bindings/{swift,kotlin} 为 UniFFI 生成物（入库）
├── mihomo-mobile/      Go：嵌入式 mihomo 的 C ABI（iOS c-archive / Android c-shared）
├── contract/           ZephyrEngine 接口契约、Mock 数据规格、共享校验样本 fixtures/、三端术语 i18n/
├── tokens/             设计 token：桌面 token（子模块）+ mobile.json → generated/{ios,android}（禁止手改）
├── tools/              构建与校验脚本（原生库构建、绑定生成、契约/样本/术语检查、快照套用）
├── design/             notes/ 设计规范，prototype/ 交互原型（浏览器打开 index.html）
├── docs/               性能、复用记录、审计报告等
└── vendor/zephyr       子模块：桌面版 Zephyr（只读）
```

## 准备

```sh
git clone --recurse-submodules https://github.com/Juwan-Hwang/zephyr-mobile.git
# 已克隆过：git submodule update --init --recursive
```

| 工具 | 版本（与 CI 一致） | 用途 |
|---|---|---|
| Rust | stable（含 clippy、rustfmt） | core-mobile |
| Go | 1.27 | mihomo-mobile |
| Node.js | 22 | tokens、契约/样本检查 |
| Xcode + XcodeGen | Xcode 16+（macOS 15），`brew install xcodegen` | iOS |
| JDK + Android SDK/NDK | Temurin 21，platform 37，NDK（`ANDROID_NDK_HOME`），`cargo install cargo-ndk` | Android |
| shellcheck / actionlint | — | tools/*.sh、workflow 检查 |

## 本地构建与测试（与 `.github/workflows/mobile.yml` 一致）

CI 有四个 job：`contract`、`core`、`ios`、`android`。PR 只跑受影响的平台：改了共享层（core-mobile/、mihomo-mobile/、tokens/、contract/、tools/、vendor/、.github/）两端都跑。

### contract：token、样本、契约、术语

```sh
node tokens/build.mjs --check                                   # token 产物最新（去掉 --check 即重新生成）
node tools/gen-mock-fixtures.js && git diff --exit-code contract/fixtures
node tools/gen-command-parse-fixtures.mjs --check
node tools/check-contract-exports.mjs                           # 每个 UniFFI 导出都写进契约
node tools/check-fixtures.mjs
node tools/check-glossary.mjs                                   # 三端术语对齐
shellcheck tools/*.sh
```

### core：Rust 核心与嵌入式 mihomo

```sh
cd core-mobile
cargo fmt --check
cargo clippy --lib --tests -- -D warnings
RUSTDOCFLAGS='-D warnings' cargo doc --no-deps --lib
cargo test --lib
cargo test --release --test full_scale -- --ignored             # 全量 1310 万节点对照原型（较慢）
cd ..
tools/gen-bindings.sh --check                                   # UniFFI 绑定无漂移（去掉 --check 即重新生成）

cd mihomo-mobile
go test -count=1 ./...
gofmt -l . && go vet ./...
```

### iOS（macOS）

```sh
tools/build-ios-xcframework.sh          # → build/ios/ZephyrMobileCore.xcframework
tools/build-mihomo.sh ios               # → build/ios/Zmihomo.xcframework
cd apps/ios
xcodegen generate                       # 或 scripts/bootstrap.sh
xcodebuild -project Zephyr.xcodeproj -scheme Zephyr \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

快照参考图按 iPhone 16（393×852）录制。更多见 [apps/ios/README.md](apps/ios/README.md)。

### Android

```sh
ABIS="arm64-v8a x86_64" tools/build-android-libs.sh   # core-mobile .so → apps/android/core-engine/src/main/jniLibs（不入库）
ABIS="arm64-v8a x86_64" tools/build-mihomo.sh android # libzmihomo.so → 同上
cd apps/android
./gradlew -Pzephyr.rust=true assembleDebug testDebugUnitTest verifyPaparazziDebug
```

- `-Pzephyr.rust=true`：使用真实 Rust 核心；不加时走 MockEngine 回退（JVM 截图测试即如此）。
- `-Pzephyr.demo=true`：以原型的“已连接 2:14:07”演示状态启动。
- `-Pzephyr.strict16k=true`：原生库未 16 KB 页对齐时构建失败（默认只告警）。

### 快照基线重录

token 改动后可在 Actions 手动运行 `mobile` workflow，勾选 `record_ios_snapshots` / `record_android_snapshots`，再用
`tools/apply-snapshot-artifacts.sh <run-id> [--ios] [--android] [--dark-only]` 把 artifact 套到工作区，由平台负责人审核后提交。

### 原型

```sh
cd design/prototype && python3 -m http.server   # 打开 index.html，左侧切换 25 个章节
```

## 发布

发布清单与签名、上架步骤见 [docs/release.md](docs/release.md)；第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

本仓库的许可证尚未确定（嵌入的 mihomo 为 GPL-3.0，需用户决定），在此之前暂不添加根目录 LICENSE。
