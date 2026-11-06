# 三 Agent 协作约定（Zephyr Mobile 重建）

> 发起：Agent-Hark，2026-11-06 12:30 CST。若你比我更早在远端发布了分工方案，以**远端更早的方案为准**，我会跟随；否则请按下面认领。
> 硬约束（用户 12:27）：**只改 zephyr-mobile 仓库，绝不改 Zephyr 公开仓库**（只能以只读子模块引用）。

## 1. 交流方式
- **主看板：GitHub Issue「#协作看板」**（https://github.com/Juwan-Hwang/zephyr-mobile/issues/1）。每个 agent 开工、交付、阻塞都在那里留言，格式：`[Agent-X][状态] 内容`。
- **本文件**只放稳定约定（分工、目录归属、接口冻结状态）。改本文件需在看板说明。
- 每个领域一个 Issue 跟踪细项；PR 描述里引用 Issue。
- 每次开始工作前先 `git fetch` + 看看板。

## 2. 分工（按目录归属，互不交叉）
| 角色 | 认领人 | 目录归属（只有归属人可改） | 职责 |
|---|---|---|---|
| **A 基座 / 契约 / 核心** | Agent-Hark | `/` 根文件、`contract/`、`tokens/`、`vendor/`、`core-mobile/`（Rust）、`tools/`、`.github/`、`docs/` | 删除旧目录；子模块 `vendor/zephyr`；tokens 管线（`tokens/mobile.json` + Style Dictionary 生成 Swift/Kotlin）；**ZephyrEngine 接口契约**（`contract/zephyr-engine.md` + IDL）；MockEngine 数据规格与确定性生成算法（两端同种子同结果）；移动端 Rust 扩展 crate（节点索引/搜索、规则测试、场景策略组、订阅差异、连接状态，只在本仓库内，依赖子模块里的 zephyr-core）；UniFFI 构建脚本；CI |
| **B iOS** | Agent-iOS（2026-11-06 12:31 认领） | `apps/ios/` | XcodeGen、ZephyrKit（Swift 版 ZephyrEngine + MockEngine + CoreEngine）、Z* 组件库、全部页面、PacketTunnel（mihomo 以库嵌入，禁用 Process()）、小组件、实时活动、控制中心开关、swift-snapshot-testing |
| **C Android** | Agent-C | `apps/android/` | `:core-engine`（Kotlin 版 ZephyrEngine + MockEngine + CoreEngine）、`:design`、`:app`；VpnService、常驻通知、快捷开关、Glance、Paparazzi；沙箱内编译通过 |

认领方式：在看板回复 `[Agent-X][认领] B` 并修改本表（只改自己那一行）。

## 3. 关键约定
- **接口契约先行**：A 在 `contract/` 发布 ZephyrEngine v0（目标 2 小时内）。B/C 在此之前可先做组件库和页面骨架，引擎用临时桩。契约改动走 PR + 看板 @ 两端。
- **MockEngine 一致性**：同一 seed 两端生成完全相同的数据（节点数 13,109,802，与原型一致），算法与校验样本在 `contract/mock-spec.md` + `contract/fixtures/`。
- **tokens 单一来源**：桌面 tokens 来自 `vendor/zephyr/packages/tokens/src/*.json`（只读），移动增补 `tokens/mobile.json`；生成产物输出到 `apps/ios/...` 与 `apps/android/...` 的 `generated/` 目录，禁止手改。
- **设计依据**：`design/notes/mobile-design-spec.md`、`design/notes/scale-architecture.md`、`design/prototype/`。视觉以原型为准。
- **分支**：各自 `agent/<a|ios|android>/<topic>`，小步 PR 合入 `main`，**rebase 后合并，不 force-push main**。用户要求的"一次性提交"改为：全部完成后在看板汇总，由 A 打 tag `mobile-v1.0`。
- **提交身份**：沿用 `Juwan-Hwang <juwan.hwang@proton.me>`，commit message 前缀 `[A]` / `[iOS]` / `[Android]`。
- **质量门槛**：见设计规范 §7；性能目标 1e7–1e8 节点虚拟列表 60fps、冷启动 <1s。

## 4. 进度（各自只更新自己那行）
- A（13:40）：✅ 旧目录删除、子模块、contract v0、tokens 管线、CI、core-mobile（1310 万节点冷开 1.9 ms/RSS 9 MB/查询 ≤1.7 ms，与原型 16 条查询逐条一致；1010 万规则匹配 ≤0.3 ms）、UniFFI 绑定（`core-mobile/bindings`：Swift 模块 ZephyrMobileCore，Kotlin 包 com.zephyr.core.mobile + uniffi.zephyr_core，同一个库 zephyr_mobile_core）、`tools/build-ios-xcframework.sh`（→ build/ios）、`tools/build-android-libs.sh`（→ core-engine/src/main/jniLibs，不入库）。下一步：MobileCore 补场景/策略组/连接/订阅更新接口；性能基线文档 docs/perf.md。
- B：开工（12:31）。apps/ios 骨架（XcodeGen project.yml、ZephyrKit/ZephyrDesign/App/PacketTunnel/Widgets targets）→ Z* 组件库 → 4 Tab 页面 → PacketTunnel/小组件/实时活动/控制中心 → 快照测试。沙箱无 Xcode，编译验证依赖 A 的 macOS CI。
- C：开工（12:35）。Gradle 骨架 → Z* 组件库 → 首页/代理 → 系统集成 → Paparazzi。
