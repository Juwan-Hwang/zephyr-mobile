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
| **A 基座 / 契约 / 核心** | Agent-Hark | `/` 根文件、`contract/`、`tokens/`、`vendor/`、`core-mobile/`（Rust）、`mihomo-mobile/`（Go，嵌入式 mihomo）、`tools/`、`.github/`、`docs/` | 删除旧目录；子模块 `vendor/zephyr`；tokens 管线（`tokens/mobile.json` + Style Dictionary 生成 Swift/Kotlin）；**ZephyrEngine 接口契约**（`contract/zephyr-engine.md` + IDL）；MockEngine 数据规格与确定性生成算法（两端同种子同结果）；移动端 Rust 扩展 crate（节点索引/搜索、规则测试、场景策略组、订阅差异、连接状态，只在本仓库内，依赖子模块里的 zephyr-core）；UniFFI 构建脚本；CI |
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
- A（16:50）：✅ 基座（contract v0+§13+§14、tokens、CI 三端、core-mobile、UniFFI 绑定、mihomo-mobile C ABI）；订阅/延迟/fastestNodes/runtimeConfig/MihomoClient；场景+覆写+storageInfo；场景自动切换（failover）；规则层 0「Zephyr 覆写」；与桌面 zephyr-core 重叠部分一律复用（清单 docs/desktop-reuse.md）。性能：1310 万节点冷开 1.9 ms/RSS 9 MB，查询 ≤1.7 ms，冷开 fastestNodes ~2 ms。已合 PR #4（Android，CI 全绿）。PR #3：A 补了缺失测试目录、ZMetrics 可见性，等 macOS CI。待真机：iOS NE 50 MB 上限。
  - A（11-14 04:00）：回应 B/C 待 A 项——①浅色 `screen.t3`/`latency.unknown` 0.4→0.55（WCAG AA，PR #37；Android Paparazzi 浅色基线需 C 审核重录，CI 已加 `workflow_dispatch: record_android_snapshots` 产出 `android-snapshots` artifact；`ZephyrWidget.kt` 硬编码 t3 需同步 0x8C000000）；②桌面同步二维码格式 = 契约 §15 + `parseImportPayload` + 样本 `contract/fixtures/import-payload-v1.json`（PR #42，解 B 的 X-P1-11）；③`motion.undo-window` 4s→5s 对齐原型（PR #44，解 C 的 H-P2-14）；④`hostOverride` / `hostTrace` / `recentHosts` 已在 §13/§14 与 core-mobile 提供（B 的 #41 已接）。
  - A（11-14 14:55）：⑤契约 §15.b 指令解析共享样本 28 例（PR #66）；⑥core clippy 零警告，CI core job 加 `clippy -D warnings`（PR #100）；⑦§15.c `nodeFunnel` 场景漏斗计数（订阅数/节点数/已测/可连通/低于阈值，PR #101，解 C H-P1-8 / B H-P2-9）；⑧§15.d `scanTargets` 扫描目标，`ScanProgress` 定为平台本地（PR #117，解 C H-P1-12 / B H-P1-5 的 scan）。#37 现只剩深色 t3 0.4→0.5，等 B/C 重录 dark 基线（iOS 47 张、Android Paparazzi + `ZephyrWidget.kt` 夜间 0x80FFFFFF）。
  - A（11-15 03:40）：⑨CI 手动重录 iOS 快照入口 `record_ios_snapshots`（PR #125，与 Android 对称）；⑩原生库缓存命中时跳过 Rust 安装与 rust-cache（PR #127，iOS/Android 各省约 1 分钟）；⑪`tools/apply-snapshot-artifacts.sh <run-id> [--ios] [--android] [--dark-only]` 把重录 artifact 套到工作区、只留深色（PR #135）。#37 已 rebase，重录图包在 run 43577692053，等 B/C 用上面脚本审核提交深色基线（C 另需 `ZephyrWidget.kt` 夜间 t3 0x80FFFFFF）。
- B（11-09 04:45）：REVIEW-Q1 的 P0/P1 已清零；REVIEW-Q2 P0 已修、P1 已修 1/4/5/9/12/14/15/16/17，6/7/10 部分。#28–#30 已合；PR（agent/ios/review-q2d）：String 文案全面本地化（ZL）、场景自动重测、增强对比度、updateAll/importFile 修复。下一批：P1-8 测试守门+快照入库（等 A 的 ios-snapshots artifact）、P1-3 事件流重复订阅、P1-11 桌面导入（等 A 的二维码格式）、P1-7 配置多份拷贝。待 A：hostOverride 读接口、connectionTrace/recentHosts、浅色 t3 对比度（见 #1）。
- C：开工（12:35）。Gradle 骨架 → Z* 组件库 → 首页/代理 → 系统集成 → Paparazzi。
