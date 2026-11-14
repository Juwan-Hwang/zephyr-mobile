# REVIEW-Q2 · Zephyr iOS 发布就绪审查（Q2，静态）

- 来源：审查员 Q2 2026-11-08 17:39（基于 main de1e23f）+ 11-08 子代理遗留清单；B 于 2026-11-09 整理为正式文件。行号会漂移，以当前代码为准。
- 格式同 Q1：唯一 ID、文件、问题、建议。状态由 B 维护：**[已修]** / 未标 = 待做 / 〔等 A〕= 需契约。

## 修复进度（B 维护）

- 2026-11-09 PR agent/ios/review-q2：[已修] X-P0-1、X-P0-2、X-P1-4（withDeadline）、X-P1-9（本地化主体：App + Widgets 目录与英文、Text(verbatim:) 用户文案改可本地化、knownRegions、InfoPlist）、X-P1-12（setSceneSource / overrideHost / globalNodeId 接 UI）、X-P1-17（空库首次导入后场景流恢复）、X-P1-3（部分：TunnelController 缓存 manager，provider 消息不再每条 loadAllFromPreferences）、X-P1-15、X-P1-16；P2：queries/remapped 限 64 项、协议默认实现改抛 unsupported（Mock 补 overrideHost）。

- 2026-11-09 PR #29（agent/ios/review-q2b）：[已修] X-P1-1（外部链接导入先弹确认，显示来源域名，http 另警告；ImportRequest 单测）、X-P1-6（断开时配置变更与首个订阅导入也写出 config.yaml；扩展侧连接无配置时明确报错）、X-P1-14（AppBootstrap：启动屏先出，引擎在后台线程加载，深链排队回放）、X-P1-7（IPv6 关闭时仍收默认路由防泄露；睡眠停 1 Hz 定时器，wake 重建；配置多份拷贝待做）、X-P1-9 余项（ErrorText 改 String(localized:)）、X-P1-12 余项（规则页“+”→ RuleAddSheet → overrideHost 持久覆写）；P2：代理凭据存钥匙串并迁移旧值、启动屏背景色与 screenBg 一致、LaunchBackground。待用户确认：ITSAppUsesNonExemptEncryption（出口合规声明由账号持有人决定，未加）。

- 2026-11-09 PR #29 续：[部分已修] X-P1-5——订阅自动更新（BGAppRefreshTask `app.zephyr.mobile.refresh` + 回前台检查 + 仅 Wi‑Fi 以 NWPath 判断；AutoUpdatePlanner 有单测；EngineHost 让前后台共用同一核心实例）、按需连接 / 受信任 Wi‑Fi 自动断开（OnDemandPlan → NEOnDemandRule，连接前与设置变更时写入系统配置）。剩余：仅 Wi‑Fi 测速（需区分手动 / 自动测速）、延迟 TTL、自动故障转移（reportSceneProbe）、场景 sheet“每日检测”文案。X-P1-11 阻塞：桌面“同步到手机”二维码格式未在契约里定义〔等 A：请给出 payload 格式〕。

- 2026-11-09 PR agent/ios/review-q2d：[已修] X-P1-9 余项（`ZL` 本地化入口：ZFormat/HFormat、模型层与页面里返回 String 的文案、Widgets/Shared 的三目与可访问性文案全部走目录并补英文；`ZL.bundle` 默认 nil 使单测保持中文，App/Widgets 启动时设为 .main）、X-P1-5 余项（场景检测结果按“结果保留”过期后，回前台/后台刷新时经 VPN 自动重测，“仅 Wi‑Fi 测速”以 NWPath 判断，SceneRetestPlanner 单测）、X-P1-10（增强对比度：`ZColor.t2/t3` 加深次级/三级文字，全部引用已迁移；正常对比度下浅色 t3 偏淡属 tokens，已在 #1 请 A 上调）；P2：updateAll 只重载隧道一次且全部失败时报错、importFile 后台读取、删除与 localhost 矛盾的 NSLocalNetworkUsageDescription、时钟遵循 12/24 小时设置。新增 TextTests / LocalizationTests / SceneRetestPlannerTests。

- 2026-11-09 PR agent/ios/review-q2e：[已修] X-P1-3 流量流（AppModel 与 SharedStatePublisher 共用一次 1 Hz 轮询，`SharedBroadcast`，有单测；场景/设置流仍各自订阅）、AppShortcuts.xcstrings（Siri 短语英文）、PacketTunnel 错误文案本地化（PacketTunnel/Localizable.xcstrings）、X-P1-8 部分（AppModelTests：流落地/连接断开/模式/导航/指令层/深链确认）；Q1 H-P2-21（外部 zephyr://connect|disconnect|mode 先弹确认，导航类不确认，DeepLinkPolicy 接入 AppModel.open(source:)）、H-P2-22（Intent 不再误用残留 lastError）、H-P2-19（recentTraffic 离主线程）、L-P2-8（节点页请求失败退避重试）、D-P2-3（SceneSheet 标题 verbatim）、DarwinObservation 回调竞态（弱引用上下文令牌）。核对确认已在先前批次完成：L-P2-3、L-P2-10、H-P2-13、W-P2-5、W-P2-6、D-P2-4。

- 2026-11-09 PR agent/ios/review-q2e 续（快照首批人工审核，取自 harvest 的 115 张 CI 渲染图）：对照 design/prototype/shots 发现并修复——① 快照渲染器重复计入模拟器安全区（页面标题下移约 59pt、小组件上下被裁）：改为量出宿主自带安全区后只补差值；② 速率数字/曲线/延迟药丸在截图瞬间处于 numericText 滚动与缓入中（“2.8”的 8 模糊、曲线几乎平）：新增环境值 `zStaticRendering`（仅快照注入）关闭这些动画，并在渲染期间关闭 UIKit 动画；③ 小组件“x 分钟前”随真实时钟变化，快照夹具去掉该行；④ 首页顶栏/底部指令栏在 AX5 下占据半屏：限定到 AX2/AX1；⑤ 节点行协议列（TUIC/Hy2…）在截图中缺失：加 NodeCellTests 断言布局（若 CI 失败再追根）。其余页面（资料库、规则、设置、订阅、引导、今日卡、锁屏/灵动岛）与原型一致，待重录后入库。快照入库仍需再取一轮干净图（修复 ①② 之后）。
- 2026-11-09 SharedBroadcast：上游流改为 subscribe 内同步创建，修复 CI 红的 testTwoSubscribersShareOneUpstream。
- 2026-11-09 PR agent/ios/review-q2g：X-P1-8 部分（ZephyrKit/ZephyrMock 开启 StrictConcurrency 完整检查，零警告）。
- 2026-11-14 PR agent/ios/review-q2i：[已修] X-P1-3 余项（`SharedBroadcast(replayLatest:)`：场景与连接状态流共享一个上游，场景只有一份 5 s 轮询，晚到订阅者立即拿到最新值；单测补回放/不回放两例）。
- 2026-11-14 PR agent/ios/review-q2j：[已修] X-P1-5 余项——延迟有效期取设置 `latencyTtlHours`（CoreEngine.latencyFreshMillis，此前写死 24 h）；场景自动切换：`ZephyrEngine.sceneFailovers()` + `CoreEngine+Failover.swift`，App 前台且隧道已连接时每 60 s 一轮，按策略组 `selected` 测可达性后 `reportSceneProbe`，核心返回切换即 `selectInGroup`（不重载），首页吐司“已自动切换到 xx（撤销）”；AI 场景只提示不上报、不切换（§14.y，与 Android 同规则）。AppModelTests 补两例。
- 2026-11-14 PR agent/ios/trace-live：[已修] X-P1-13（`ZephyrEngine.hostTrace(host:)` → MihomoClient.hostTrace；TraceSteps 以实测规则 / 场景 / 节点为准，“经由 <中间组>”，与预测规则不一致标“实际匹配”；lede 用实测连接数与流量）、X-P1-12 余项（`hostOverride(host:)` 回填覆写分段）。TraceStepsTests 补四例。

- 2026-11-14 PR agent/ios/link-tests：X-P1-8 部分——新增不托管测试 target `ZephyrAppTests`，`SharedStatePublisherTests` 覆盖：显著变化判定（连接状态/模式、场景形状 vs 延迟数值）、场景截 4 个、断开速率归零且时间戳刷新、首写立即落盘 / 5 s 节流 / 显著变化带出排队速率、只合并脏字段、盘上更新的速率胜出并回填内存与 onChange、用量映射。AppServices 链接解析（`ImportRequest.subscriptionURL`）已由 `Shared/Tests/ImportRequestTests` 覆盖，核对确认。
- 2026-11-14 PR agent/ios/no-color-only：X-P1-10 部分——「不以颜色区分」开启时 ZStatusDot 以形状编码三态（关空心环、开实心圆、覆盖色警示态实心菱形），首页连接点与订阅差异卡受益；延迟读数本身带数字/“超时”文字，无需改。

- 2026-11-14 PR agent/ios/l10n-q2b（base #51）：X-P1-9 余项——指令预览卡标题/摘要/脚注、轨迹覆写分段“不变/直连”、节点索引条与地区筛选读屏、场景候选“固定”读屏、扫码取景框读屏、订阅卡“剩余”默认值、地区筛选“全部”改走 `ZL`，xcstrings 补英文。ErrorText/HFormat/AppShortcuts 已在先前批次完成（核对）。
- 2026-11-14 PR agent/ios/scene-freq：X-P1-5 收尾——场景 sheet“检测频率”不再固定“每天”，按设置 `latencyTtlHours` 显示（24 h = 每天，否则“每 N 小时”），仅 Wi‑Fi 时加后缀；补英文。
- 2026-11-14 PR agent/ios/snapshot-refs 续：首轮 CI 22/115 不一致，查明三处不确定性并修复——今日卡流线背景 TimelineView 随墙钟（WindArt 在 zStaticRendering 下画固定帧）、半透明边缘像素取整漂移（出图改 sRGB 8 位不透明底）、参考图取自 XCTAttachment(image:) 重编码（录制附件改附写盘原字节）；锁屏圆形小组件改容量环、去掉与单位重叠的“下行”标签（对齐原型 lock.png）。参考图按新渲染重新收取。

## P0

- **Q2-X-P0-1 无隐私清单** [已修] — `App/` `PacketTunnel/` `Widgets/` 各加 `PrivacyInfo.xcprivacy`（UserDefaults CA92.1、文件时间戳 C617.1、磁盘空间 85F4.1、系统启动时间 35F9.1；不追踪、不收集）。随 target 资源打包。
- **Q2-X-P0-2 Release 会显示假数据** [已修] — `App/EngineFactory.swift`：Release 核心加载失败不再回落 MockEngine，改为 `CoreUnavailableView`；`LaunchEnvironment` 的 `-ZephyrEngine/-ZephyrClock/-ZephyrSeed` 仅 Debug/模拟器生效；`Core/CoreEngine.swift` 节点库为空时 setGlobalNode / 预览与应用场景切换 / retestScene / setSceneSource / overrideHost 在非 mockData 下抛错、testLatency 与 commandSuggestions 返回空，不再转发 MockEngine。

## P1

- **Q2-X-P1-1 任意链接静默导入订阅** [已修] — `App/AppServices.swift:~202`：`clash://` / `mihomo://install-config` 无确认、接受明文 http。建议先弹审核 sheet（域名、协议、http 警告）。
- **Q2-X-P1-2 App 覆盖隧道写的共享状态** — 〔A 已在 #23 修复并经 B 复核〕保留编号。
- **Q2-X-P1-3 每秒重载 VPN 配置** [已修：manager 缓存；流量/场景/连接状态流经 SharedBroadcast 共享上游；设置/订阅流为推送式无轮询] — `TunnelController.activeSession` 每条 provider 消息都 loadAllFromPreferences；`SharedStatePublisher` 常驻流量订阅；场景/设置/连接流被 AppModel、Publisher、LibraryModel 重复订阅。建议缓存 manager，由 AppModel 扇出。
- **Q2-X-P1-4 withDeadline 超时无效** [已修] — 任务组会等全部子任务；改为两个非结构化任务竞速 + 一次性 continuation（`CoreEngine+Live.swift`），单测 `CoreTests/WithDeadlineTests.swift`。
- **Q2-X-P1-5 多项设置不生效** [已修：自动更新、按需连接、受信任 Wi‑Fi、仅 Wi‑Fi 测速、延迟 TTL、自动故障转移；“每日检测”文案（检测频率按延迟有效期显示，24 h 仍为“每天”）] — 按需连接 / 受信任 Wi‑Fi 自动断开（无 NEOnDemandRule）、订阅自动更新（dueSubscriptions/后台任务未用）、仅 Wi‑Fi 测速、延迟 TTL 写死、自动故障转移（reportSceneProbe 未调用）；场景 sheet “每日检测”不属实。
- **Q2-X-P1-6 控制中心/小组件连接用旧配置** [已修] — `TunnelController.setConnected` 不重新生成 config.yaml，首次从小组件连接失败；`reloadTunnelIfRunning` 断开时不写配置。
- **Q2-X-P1-7 PacketTunnel 内存与电量** [已修：IPv6 路由、睡眠定时器、MappedFile 映射读取配置] — 配置被复制 5–6 次；1 Hz 定时器睡眠时仍唤醒；IPv6 关闭时未声明 IPv6 路由导致绕过隧道（隐私泄露）。
- **Q2-X-P1-8 测试不守门** [已修：参考图入库（#58）且录制模式 never、缺图即失败；容差 0.995/0.98；AppModel / SharedStatePublisher / 链接解析 / LiveActivityPolicy 单测与实时活动快照；SPM 目标严格并发 complete；App、PacketTunnel、Widgets 已切 Swift 6（#92–#94，并发警告清零）。快照 bundle 不托管为有意设计，语言变体经临时 en.lproj bundle 覆盖（#88）。余：layer.render 不含系统模糊材质，改 drawHierarchy 需全量重录，暂列已知限制] — `__Snapshots__` 空且录制模式 missing，永不比对；快照 bundle 无 TEST_HOST；`layer.render` 丢模糊材质；容差 0.99/0.98 偏松；缺 AppModel、SharedStatePublisher、AppServices 链接解析、LiveActivity 测试；SPM target 无严格并发设置，App 仍 Swift 5 模式。
- **Q2-X-P1-9 本地化** [已修，余漏网文案见下] — App 与 Widgets 的 `Localizable.xcstrings` 已生成（zh-Hans 源 + en，373 key，含复数），`Text(verbatim:)` 用户文案已改可本地化，`InfoPlist.xcstrings`（相机/相册/本地网络说明）、project.yml `knownRegions`/`CFBundleLocalizations` 已加。剩余：返回 String 的文案（ErrorText、HFormat、ZSettingsRow(verbatim:)、AppShortcuts、Live Activity 状态文字）需改 `String(localized:)`；英文版快照；伪语言（加长）布局测试。
  - 2026-11-14 PR #88：英文 / 伪语言快照（首页、设置、订阅、引导、连接 en-dark 与 pseudo-dark，首页加 pseudo-dark-ax5）。快照渲染期间 `+mainBundle` 返回只含 en.lproj 的临时 bundle，SwiftUI 字面量与 `ZL` 都查到英文。伪语言图暴露的漏网文案（下一批）：引导页标题“添加订阅”与脚注“订阅与流量数据仅保存在此设备上。”、设置“应用图标”“跟随系统”“24 小时”“无需密码”“家”、订阅“每 12 小时”。
- **Q2-X-P1-10 对比度与显示辅助** [部分已修：增强对比度；不以颜色区分（ZStatusDot 关=空心环/开=实心圆/警示=菱形）；浅色 t3 基色等 A 的 tokens；降低透明度由系统材质处理] — 浅色 t3 仅 2.8:1、深色 3.7:1；不支持增强对比度、降低透明度、不以颜色区分。
- **Q2-X-P1-10 对比度与显示辅助** [部分已修：增强对比度；浅色 t3 已由 A 在 f1fa0ce 提到 0.55（WCAG AA）；降低透明度由系统材质处理] — 浅色 t3 仅 2.8:1、深色 3.7:1；不支持增强对比度、降低透明度、不以颜色区分。
- **Q2-X-P1-11 “从桌面 Zephyr 导入”在真引擎必败** [已修：#54 按契约 §15 解析桌面导入码] — `CoreEngine.swift:~529` 拒绝非 URL 二维码。
- **Q2-X-P1-12 新接口未接 UI** [已修] — SceneSheet 来源分段 → `AppModel.setSceneSource`；TraceView 底部 `TraceOverrideSection` → `AppModel.overrideHost`（直连/场景、始终应用、撤销吐司）；`CoreEngine.connectionState()` 在全局模式补 `globalNodeId`（冷启动即有出口节点，setGlobalNode 后重发）；Scene.services 行此前已接。剩余：RuleAddSheet 接 overrideHost；~~`hostOverride` 读接口回填当前覆写~~ [已修：TraceOverrideSection 打开时回填分段与“始终应用”]。
- **Q2-X-P1-13 连接轨迹用 App 侧 testRule 预测，不是 mihomo 实际匹配** [已修：隧道连接时用 MihomoClient.hostTrace 实测（规则、策略链、节点），预测仅作回落]。
- **Q2-X-P1-14 MobileCore 在 App.init 主线程同步初始化，拖慢冷启动** [已修] — 建议移到后台 Task，先呈现启动画面。
- **Q2-X-P1-15 场景延迟算作“显著变化”，反复 reload 全部小组件时间线** [已修：只比较场景集合/出口/延迟档位]。
- **Q2-X-P1-16 scenePhase .inactive 会切断流量流** [已修：仅 .background 暂停]。
- **Q2-X-P1-17 空库首次导入后场景流不再恢复轮询** [已修] — `CoreEngine.scenes()` 空库时每 1.5 s 复查节点库，有数据即恢复 5 s 轮询。

## P2

- ~~启动屏颜色与 App 背景不一致~~ [已修]
- [已修] 无深色/着色 App 图标变体（AppIcon-Light 资源与 `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`）。
- ~~`NSLocalNetworkUsageDescription` 与只绑 localhost 矛盾~~ [已修]；缺 `ITSAppUsesNonExemptEncryption`（待用户决定）。
- ~~代理凭据存 UserDefaults，应进 Keychain~~ [已修]
- ~~CoreEngine queries/remapped 无限增长~~ [已修]；~~协议默认 no-op~~ [已修]。
- ~~DarwinObservation deinit 与回调竞态~~ [已修]；~~CoreEngine `queries`/`remapped` 字典无限增长~~ [已修]。
- ~~`updateAll` 吞错误且重载隧道 N 次~~ [已修]；~~订阅导入无进度/取消~~ [已修：导入中显示进度并可取消，晚到结果丢弃、新建条目撤回]；~~无日志/诊断 UI~~ [已修：设置 › 诊断 › 日志，级别筛选/暂停/清空/分享]；~~`importFile` 主线程读文件~~ [已修]。
- [已修] 协议扩展里 `setSceneSource`/`overrideHost` 默认静默 no-op（应改为必须实现或抛 unsupported）。
- [已修] L-P2-7 registerForTraitChanges；L-P2-8 已有重试。
- 原型“检测中 138/512”进度未显示；~~时钟格式忽略 12/24 小时~~ [已修]。
- ~~CI 性能测试用墙钟易抖；覆盖率只统计 App target~~ [已修：计时改单调时钟、只断言下限、上限仅防挂死；覆盖率加扩展与 ZephyrKit 各库]。
- 11-08 子代理遗留：~~RuleAddSheet 接 overrideHost~~ [已修]；NodeRowStore 失败重试（L-P2-8）；订阅/节点/规则错误横幅（L-P2-11）；其余文件 #if DEBUG 包裹 Mock（L-P2-5）；引导节奏（L-P2-2）；registerForTraitChanges（L-P2-7）；L-P2-12/13/4；深链来源（H-P2-21：AppModel.pendingLink、确认弹窗、小组件 URL 令牌）；H-P2-10/11/~~14~~[已修：关闭连接后吐司反馈成功/失败数]/15/16/~~18~~[已修：指令层预取失败静默]/19[已修：recentTraffic 移出主线程]/20[不改：Swift 6 @Observable 生成 _modify 原地修改；视图持有副本时 1 Hz 拷贝 300×24 B 可忽略]；D：ZTrafficStat/ZSparkline 颜色改 accent/screenUp、ZLatencyPill 注释、SceneSheet 改 ZSheet(verbatim:)、Features 采用 ZGroupCard。
