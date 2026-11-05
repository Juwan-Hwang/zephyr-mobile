# Zephyr Mobile (Android & iOS)

Zephyr 移动端双平台原生应用工程仓库，涵盖完整 Android (Kotlin / Jetpack Compose) 与 iOS (Swift / SwiftUI) 原生客户端实现及 UniFFI 跨平台迁移体系。

---

## 目录结构

```
zephyr-mobile/
├── android/                        # Android 原生项目 (Kotlin + Jetpack Compose)
│   ├── app/
│   │   ├── src/main/java/          # Compose UI, ViewModel, VpnService, MihomoProcessManager
│   │   ├── src/main/jniLibs/       # arm64-v8a / x86_64 prebuilt native libraries
│   │   ├── src/main/assets/core/   # Mihomo 内核包
│   │   └── build.gradle.kts
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── ios/                            # iOS 原生项目 (Swift + SwiftUI + NetworkExtension)
│   ├── Package.swift               # SPM 包定义
│   └── Sources/
│       ├── ZephyrApp/              # SwiftUI 主程序及 5-tab 页面
│       ├── PacketTunnel/           # NEPacketTunnelProvider 网络扩展
│       ├── DesignSystem/           # SwiftUI 设计系统与 Token
│       └── UniFFI/                 # Rust zephyr_core UniFFI 绑定
├── tokens/                         # Design Tokens 源配置 (Style Dictionary)
│   ├── config.js
│   └── src/                        # primitive, semantic, component token json
├── scripts/                        # 构建与生成脚本
│   ├── prebuild_mobile.sh          # 移动端预构建流水线
│   └── build_ios.sh                # iOS XCFramework 构建脚本
└── uniffi-migration-v4.7-FINAL.md  # Rust UniFFI + 原生 UI 移动端迁移工作流 v4.7 完整手册
```

---

## 架构说明

1. **Android 端**
   * **UI 框架**：Jetpack Compose，提供 Home, Proxies, Profiles, Logs, Settings 5 大 Tab 页面与平滑动效。
   * **网络底层**：基于 Android 官方 `VpnService`，搭配进程管理器 `MihomoProcessManager` 和 API 客户端 `MihomoApi`。
   * **跨平台核心**：通过 `jniLibs` 和 UniFFI 驱动 `zephyr_core`。

2. **iOS 端**
   * **UI 框架**：SwiftUI，界面交互与设计 Token 与 Android 保持 1:1 对齐。
   * **网络扩展**：基于 Apple `NetworkExtension` 的 `ZephyrPacketTunnelProvider`。
   * **跨平台核心**：通过 UniFFI 自动生成的 `zephyr_core.swift` 调用 Rust 核心库。

3. **迁移指南**
   * 详见 [uniffi-migration-v4.7-FINAL.md](./uniffi-migration-v4.7-FINAL.md)。
