# REVIEW-Q2 · Zephyr iOS 发布就绪审查（Q2，静态）

- 来源：审查员 Q2 2026-11-08 17:39（基于 main de1e23f）+ 11-08 子代理遗留清单；B 于 2026-11-09 整理为正式文件。行号会漂移，以当前代码为准。
- 格式同 Q1：唯一 ID、文件、问题、建议。状态由 B 维护：**[已修]** / 未标 = 待做 / 〔等 A〕= 需契约。

## 修复进度（B 维护）

- 2026-11-09 PR agent/ios/review-q2：[已修] X-P0-1、X-P0-2、X-P1-4（withDeadline）、X-P1-9（本地化主体：App + Widgets 目录与英文、Text(verbatim:) 用户文案改可本地化、knownRegions、InfoPlist）、X-P1-12（setSceneSource / overrideHost / globalNodeId 接 UI）、X-P1-17（空库首次导入后场景流恢复）、X-P1-3（部分：TunnelController 缓存 manager，provider 消息不再每条 loadAllFromPreferences）、X-P1-15、X-P1-16；P2：queries/remapped 限 64 项、协议默认实现改抛 unsupported（Mock 补 overrideHost）。

## P0

- **Q2-X-P0-1 无隐私清单** [已修] — `App/` `PacketTunnel/` `Widgets/` 各加 `PrivacyInfo.xcprivacy`（UserDefaults CA92.1、文件时间戳 C617.1、磁盘空间 85F4.1、系统启动时间 35F9.1；不追踪、不收集）。随 target 资源打包。
- **Q2-X-P0-2 Release 会显示假数据** [已修] — `App/EngineFactory.swift`：Release 核心加载失败不再回落 MockEngine，改为 `CoreUnavailableView`；`LaunchEnvironment` 的 `-ZephyrEngine/-ZephyrClock/-ZephyrSeed` 仅 Debug/模拟器生效；`Core/CoreEngine.swift` 节点库为空时 setGlobalNode / 预览与应用场景切换 / retestScene / setSceneSource / overrideHost 在非 mockData 下抛错、testLatency 与 commandSuggestions 返回空，不再转发 MockEngine。

## P1

- **Q2-X-P1-1 任意链接静默导入订阅** — `App/AppServices.swift:~202`：`clash://` / `mihomo://install-config` 无确认、接受明文 http。建议先弹审核 sheet（域名、协议、http 警告）。
- **Q2-X-P1-2 App 覆盖隧道写的共享状态** — 〔A 已在 #23 修复并经 B 复核〕保留编号。
- **Q2-X-P1-3 每秒重载 VPN 配置** [部分已修：manager 缓存；事件流重复订阅待做] — `TunnelController.activeSession` 每条 provider 消息都 loadAllFromPreferences；`SharedStatePublisher` 常驻流量订阅；场景/设置/连接流被 AppModel、Publisher、LibraryModel 重复订阅。建议缓存 manager，由 AppModel 扇出。
- **Q2-X-P1-4 withDeadline 超时无效** [已修] — 任务组会等全部子任务；改为两个非结构化任务竞速 + 一次性 continuation（`CoreEngine+Live.swift`），单测 `CoreTests/WithDeadlineTests.swift`。
- **Q2-X-P1-5 多项设置不生效** — 按需连接 / 受信任 Wi‑Fi 自动断开（无 NEOnDemandRule）、订阅自动更新（dueSubscriptions/后台任务未用）、仅 Wi‑Fi 测速、延迟 TTL 写死、自动故障转移（reportSceneProbe 未调用）；场景 sheet “每日检测”不属实。
- **Q2-X-P1-6 控制中心/小组件连接用旧配置** — `TunnelController.setConnected` 不重新生成 config.yaml，首次从小组件连接失败；`reloadTunnelIfRunning` 断开时不写配置。
- **Q2-X-P1-7 PacketTunnel 内存与电量** — 配置被复制 5–6 次；1 Hz 定时器睡眠时仍唤醒；IPv6 关闭时未声明 IPv6 路由导致绕过隧道（隐私泄露）。
- **Q2-X-P1-8 测试不守门** — `__Snapshots__` 空且录制模式 missing，永不比对；快照 bundle 无 TEST_HOST；`layer.render` 丢模糊材质；容差 0.99/0.98 偏松；缺 AppModel、SharedStatePublisher、AppServices 链接解析、LiveActivity 测试；SPM target 无严格并发设置，App 仍 Swift 5 模式。
- **Q2-X-P1-9 本地化** [部分已修] — App 与 Widgets 的 `Localizable.xcstrings` 已生成（zh-Hans 源 + en，373 key，含复数），`Text(verbatim:)` 用户文案已改可本地化，`InfoPlist.xcstrings`（相机/相册/本地网络说明）、project.yml `knownRegions`/`CFBundleLocalizations` 已加。剩余：返回 String 的文案（ErrorText、HFormat、ZSettingsRow(verbatim:)、AppShortcuts、Live Activity 状态文字）需改 `String(localized:)`；英文版快照；伪语言（加长）布局测试。
- **Q2-X-P1-10 对比度与显示辅助** — 浅色 t3 仅 2.8:1、深色 3.7:1；不支持增强对比度、降低透明度、不以颜色区分。
- **Q2-X-P1-11 “从桌面 Zephyr 导入”在真引擎必败** — `CoreEngine.swift:~529` 拒绝非 URL 二维码。
- **Q2-X-P1-12 新接口未接 UI** [已修] — SceneSheet 来源分段 → `AppModel.setSceneSource`；TraceView 底部 `TraceOverrideSection` → `AppModel.overrideHost`（直连/场景、始终应用、撤销吐司）；`CoreEngine.connectionState()` 在全局模式补 `globalNodeId`（冷启动即有出口节点，setGlobalNode 后重发）；Scene.services 行此前已接。剩余：RuleAddSheet 接 overrideHost；契约 `hostOverride` 读接口〔等 A〕用于回填当前覆写。
- **Q2-X-P1-13 连接轨迹用 App 侧 testRule 预测，不是 mihomo 实际匹配** 〔等 A：connectionTrace/recentHosts〕。
- **Q2-X-P1-14 MobileCore 在 App.init 主线程同步初始化，拖慢冷启动** — 建议移到后台 Task，先呈现启动画面。
- **Q2-X-P1-15 场景延迟算作“显著变化”，反复 reload 全部小组件时间线** [已修：只比较场景集合/出口/延迟档位]。
- **Q2-X-P1-16 scenePhase .inactive 会切断流量流** [已修：仅 .background 暂停]。
- **Q2-X-P1-17 空库首次导入后场景流不再恢复轮询** [已修] — `CoreEngine.scenes()` 空库时每 1.5 s 复查节点库，有数据即恢复 5 s 轮询。

## P2

- 启动屏颜色与 App 背景不一致（#0B0F19 vs #000；#F4F4F5 vs #F2F2F7）。
- 无深色/着色 App 图标变体（AppIcon-Light 资源与 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`）。
- `NSLocalNetworkUsageDescription` 与只绑 localhost 矛盾；缺 `ITSAppUsesNonExemptEncryption`。
- 代理凭据存 UserDefaults，应进 Keychain。
- ~~CoreEngine queries/remapped 无限增长~~ [已修]；~~协议默认 no-op~~ [已修]。
- DarwinObservation deinit 与回调竞态；CoreEngine `queries`/`remapped` 字典无限增长。
- `updateAll` 吞错误且重载隧道 N 次；订阅导入无进度/取消；无日志/诊断 UI；`importFile` 主线程读文件。
- 协议扩展里 `setSceneSource`/`overrideHost` 默认静默 no-op（应改为必须实现或抛 unsupported）。
- 原型“检测中 138/512”进度未显示；时钟格式忽略 12/24 小时。
- CI 性能测试用墙钟易抖；覆盖率只统计 App target。
- 11-08 子代理遗留：RuleAddSheet 接 overrideHost（直连/场景，persistent:true，撤销=.unchanged）；NodeRowStore 失败重试（L-P2-8）；订阅/节点/规则错误横幅（L-P2-11）；其余文件 #if DEBUG 包裹 Mock（L-P2-5）；引导节奏（L-P2-2）；registerForTraitChanges（L-P2-7）；L-P2-12/13/4；深链来源（H-P2-21：AppModel.pendingLink、确认弹窗、小组件 URL 令牌）；H-P2-10/11/14/15/16/18/19/20；D：ZTrafficStat/ZSparkline 颜色改 accent/screenUp、ZLatencyPill 注释、SceneSheet 改 ZSheet(verbatim:)、Features 采用 ZGroupCard。
