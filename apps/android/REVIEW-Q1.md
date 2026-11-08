# REVIEW-Q1 · Zephyr Android 对照原型审查（Q，只读）

- 分支：`agent/android/review-q1` @ `2f595c9`（本文件是本次唯一新增，未 commit；审查期间工作区出现了另一路改动 `apps/android/app/build.gradle.kts`（abiFilters + 16 KB 对齐检查，非本审查所为），本文所有行号以 `2f595c9` 为准）
- 验收标准：`design/prototype/`（index.html 内联 CSS/JS、pages.js、`shots/*.png`）、`design/notes/mobile-design-spec.md`、`tokens/mobile.json`（生成物 `tokens/generated/android/ZTokens.kt`，经 `:design` 的 sourceSet 引入）
- 范围：`apps/android/design`、`apps/android/app`、`apps/android/core-engine`（只看与 UI / 发布行为直接相关的部分）
- 方法：**静态审查**。按约定未跑 Gradle、未编译、未跑 Paparazzi；性能结论来自代码路径分析，需用 Macrobenchmark / Perfetto / Layout Inspector 的重组计数复核。
- 行号均以当前提交为准。原型尺寸按 CSS px = dp/sp 换算。原型 CSS 行号指 `design/prototype/index.html`。

## 修复进度（C 维护）

- 2026-11-08 PR agent/android/review-q1：✅ P0-1（release 不再用 Mock 填充：recentTraffic/usageToday/storage/commandSuggestions/导入/场景/轨迹/规则在无核心或无订阅时返回空或抛错；无隧道时不再显示“已连接”，状态为“连接失败 · 先添加一个订阅 / 内核未能启动”）、P0-2（指令层按原型重写：空态为示例短语只填入输入框；令牌下划线用 VisualTransformation 画在真实输入框上；“Gemini 走日本”只固定 Gemini（setSceneException），卡片带“出口 IP 将更改 from → to”与“将暂停/使用其他节点”说明；“GitHub 直连”走 overrideHost；回车只应用已预览的计划；修正 MockFixtures 运算符优先级）、W-P1-2（首次连接成功后申请通知权限）、W-P1-3（磁贴 API 分支 + lint NewApi 致命）。
- 同 PR 第二批：✅ H-P1-1（吐司上移到 AppRoot 顶层，sheet/指令层之上、离开首页也可见）、H-P1-2（首页 VM 统一 launchCatching，错误变成吐司）、H-P1-6（隐藏 sheet 不再收集/轮询，collectWhile 跟随生命周期）、H-P1-9（随指令层重写）、H-P1-10（今日卡品牌标随卡片配色、PNG 编码移出主线程）、H-P1-11（“已切换至X” / “{服务} 现使用{节点}”）。lint 修复：Android 9 上 VpnService.Builder.setMetered（API 29）会让 VPN 启动崩溃；主题的 API 29/31 属性移到 values-v29/v31；通知更新先判权限。lintDebug 现为 0 error。
- 第三批：✅ H-P1-7（全局模式卡显示真实 GLOBAL 当前节点；“更换节点”按原型 gcf 内联展开“出口 IP 将更改 / 所有 App 的出口都将变为X / [更改为X][取消]”，确认后“已切换至X”可撤销；CoreEngine.setGlobalNode 走 mihomo GLOBAL；release 下 groupMembers/selectInGroup/testGroup 不再回落 Mock）。
- 第四批（跟进 A 的 #14/#16/#17）：✅ 全局出口改用核心 previewGlobalChange/setGlobalNode/globalNode（确认行显示出口 IP from → to）；✅ H-P1-12 部分：Scene.services 映射，首页场景行“Claude 不可用 / GPT、Gemini 正常”（原型 11 zero）；服务与出口探测经 127.0.0.1 mixed 端口（本 App 不进自身 VPN，ProxyProbe 走 CONNECT + Basic 认证 + TLS），每约 10 分钟一轮、重测场景时即时一轮，只记录不切换；本地代理凭据 zephyr:<24 位随机>，未开本地代理时用私有随机端口；✅ 节点详情 nodeDetail、按需测速 latencyTestBatch → zm_url_test → recordUrlTest、testedCount 来自核心；✅ 日志接 zm_logs（1 Hz 增量，序号回退从 0 重拉）；✅ 今日用量 UsageLedger（24 小时桶 + 在线时长，计数器回退按重启处理，跨天清零，30 s 落盘、断开时落盘）；✅ 规则集：导入/更新订阅后后台拉取到期 RULE-SET 并 compileRuleProvider（mrs 跳过），后台 Worker 每轮也刷新。未在真机验证。
- 第五批（PR agent/android/geo-home）：✅ §14.v GEOSITE/GEOIP 层：refreshRuleProviders 末尾 geoSources → 下载 .dat（https、临时文件 + 原子替换，失败保留旧文件）→ compileGeo；✅ H-P1-5：1 Hz 时钟与流量/spark 拆到 HomeLive（WhileSubscribed 5 s，退后台即停 FFI 轮询），只有状态行与流量行读取；spark 用环形 FloatArray；scenes/subscriptions 改 WhileSubscribed；分钟时钟同时刷新今日用量；✅ H-P1-8：场景 sheet 去掉编造的“2 个订阅 512 个节点”与漏斗（契约无分段计数，隐藏而非编造）；补“订阅分组 / Zephyr 优选”分段（setSceneSource 接入；AI 场景选优选若会换出口，先回首页走内联确认，确认后才记录来源）；补按延迟排序的候选列表，点选走同一出口 IP 确认；“节点不可用时 / 固定 App”改为纯展示行，删除无实现的“检测频率”。✅ H-P1-4：fontScale ≥ 1.3 时场景行纵向堆叠（名称 → 可用数 → [徽标] 节点 → 锁定说明），左对齐、各 2 行，锁定说明不再截断；1.6 倍字体基准图已重录。✅ H-P1-3：场景行实时擦洗——每 42dp 跨一格，徽标与节点名就地变化，徽标 120 ms 弹跳变蓝 + SegmentFrequentTick 触感，底部 track 显示格位；格位来自场景池（每地区最快节点，当前出口占本地区格位），两端截止不循环；松手到其他格才出出口 IP 确认；TalkBack 自定义动作直接给出相邻地区节点名。✅ L-P1-1：节点/规则/订阅/设置路由带 back，来自资料库则返回时重开资料库，来自首页标签为“首页”。✅ L-P1-4：节点 chips 取 nodeIndex.sections 前 8，副标题用真实订阅数。✅ L-P1-3（部分）：导入 sheet 的“从文件导入”接 SAF OpenDocument（≤32 MB，失败提示“这不是有效的配置文件”）；扫码置灰标“即将支持”；“从电脑导入”改为中性说明；订阅页“其他 N 个”仅在 N>0 时显示且不可点；设置“受信任的 Wi‑Fi”去掉无动作 chevron。资料库三行仍跳设置首页（设置页内有对应行）。✅ L-P1-5：强调色 44dp 单选触控区、中文名、selected 语义、selectableGroup。✅ §14.u：隧道未连接时测速走 TCP 握手（TcpPinger，进程级 32 并发、3 s 超时记 -1，UDP 协议跳过），recordLatencies 写回并推 latencyUpdates；CoreParityTest.tcpPingWhenDisconnected 覆盖。
- 偏离：Compose 下划线颜色随文字色（原型为 t1 文字 + 彩色下划线）；“视频只用 4K 节点”需契约节点标签过滤，暂无计划卡。

## 总览

| 级别 | 条数 | 含义 |
|---|---|---|
| **P0** | 2 | 发布阻断：发布包显示伪造数据 / 假“已连接”；AI 出口可绕过内联确认被更改 |
| **P1** | 28 | 明显的体验 / 视觉 / 性能 / 无障碍 / 平台兼容问题，上线前应修 |
| **P2** | 52 | 打磨项，对标一线 App 应做 |

整体评价：底子比 iOS 当时好——**主题层已经正确映射 `screen.*` 色板**（`ZColors.kt:52-78` 全部取 `screenS1…S4 / Hl / T1…T4 / Green / Amber / Red / Glass`，语义色是 Apple 系统色而非 Tailwind），引导页已接入首启（`MainActivity.kt:27` + `AppRoot.kt:81`），VPN 授权只在第一次连接时弹（`MainActivity.kt:39-42`），节点搜索有 80 ms 去抖，sheet 支持预测性返回，内联确认文案“更改 GPT 和 Gemini 的出口 IP？ / SG → JP / Claude 保持不变。”在滑动路径上是对的。
差距集中在四处：**① 发布包仍经 `CoreEngine by MockEngine` 委托大量接口，没有核心时还会显示假“已连接”；② 指令层能绕过内联确认改 AI 出口（回车甚至会直接断开 VPN）；③ 多个“看得见点不动”的死路入口与写死的演示数据；④ 平台层：通知权限从不申请、QS 磁贴在 API 28–33 会崩、状态栏图标不跟随 App 外观。**

---

## P0

### P0-1 〔Release〕发布包显示 MockEngine 的伪造数据；无核心/无订阅时 VPN 显示“已连接”但没有隧道
- 文件：`core-engine/.../core/CoreEngine.kt:75`（`) : ZephyrEngine by fallback {`）、`app/.../di/AppGraph.kt:35-44`（发布包同样传入 `MockEngine`，仅 `mockData = BuildConfig.DEBUG`）、`app/.../vpn/TunBridge.kt:28-32, 62-66`、`app/.../vpn/ZephyrVpnService.kt:52-59`、`app/.../ui/home/HomeViewModel.kt:58, 71`
- 问题：
  - `mockData=false` 只覆盖了 scenes / subscriptions / nodeIndex / queryNodes / ruleStats / 活动连接等少数接口（测试 `CoreEngineLiveTest.kt:70-76` 也只验了这 4 个）。**未覆盖的接口在 release 里直接走 MockEngine**：`usageToday()`（`MockEngine.kt:116`，永远“今日 1.8 GB”→ 首页“订阅”段尾、今日卡、小组件）、`recentTraffic()`（`MockEngine.kt:110`，首页曲线连上即回填 90 个伪造样本，`HomeViewModel.kt:71`）、`storage()`（`MockEngine.kt:393`，设置页“节点 0.6 GB · 规则 1.9 GB · 可用 3.1 GB”写死）、`commandSuggestions()`（`MockEngine.kt:396`，用 mock 场景与 mock 节点 id 生成“切换”指令，再拿去调真实核心）、`connectionTrace()`（无 live 时 `CoreEngine.kt:425` 回落 mock 轨迹）、`testRule()`（规则未就绪时 `CoreEngine.kt:498` 回落 mock）、`previewSceneChange/applySceneChange`（节点未就绪时 `CoreEngine.kt:287, 293` 回落 mock IP）、`importSubscription()`（无 .so 时 `CoreEngine.kt:129` 回落 mock，**假装导入成功**）。
  - `connectionState()/connect()/disconnect()` 也来自 MockEngine（`MockEngine.kt:70-80`）。`TunBridge.pick()` 在没有 .so 或没有激活订阅时返回 `Simulated`（不建 tun），但 `ZephyrVpnService.start()` 照样 `engine.connect()` → 首页“已连接”+ 计时、常驻通知“Zephyr · 0:00:12”。**用户以为流量已走代理，实际全部直连**——对 VPN 是信任事故。
- 建议：
  - `CoreEngine` 去掉 `by fallback`，对每个契约方法显式实现；release 下 fallback 只允许 `if (mockData)`，否则返回空/抛 `NOT_RUNNING`。连接状态应由 VpnService/mihomo 真实状态驱动（`Mihomo.running` + tun 建立成功），`Simulated` 只能在 debug 存在；release 下 `pick()` 拿不到 Embedded 就让连接失败并给出“还没有可用的订阅 / 核心未打包”的提示。
  - MockEngine/MockFixtures 移到 `src/debug`（或独立 `:core-engine-mock` 只给 debug/test 依赖），让 release 物理上不链接 mock；补一条测试：`CoreEngine(mockData=false)` 下所有返回“数值”的接口均为空/0。

### P0-2 〔Command〕指令层可绕过“更改 GPT 和 Gemini 的出口 IP？”内联确认直接更改 AI 出口；回车可误断开 VPN
- 文件：`app/.../ui/command/CommandOverlay.kt:71-72, 77-86`；`app/.../ui/nav/AppRoot.kt:138-141`；`app/.../ui/home/HomeViewModel.kt:108-117`；`core-engine/.../mock/MockFixtures.kt:198-209`
- 问题：
  - 用户明确要求：AI 场景出口变化**必须**经内联确认（原型 672-675：`更改 GPT 和 Gemini 的出口 IP？` / `SG 198.51.100.7 → JP 203.0.113.61` / `Claude 保持不变。`）。滑动路径做到了，但指令路径“Gemini 走日本”→ 卡片只有标题 + “9 个可用，将使用 东京 03。”+“应用”（`CommandOverlay.kt:81-86`），**没有 from→to 出口 IP 行**（原型指令卡 `.pv .ipl`：`出口 IP 将更改 SG 198.51.100.7 → JP 203.0.113.61`，1032/1041），点“应用”即 `applySceneChange(AI, node)`（`HomeViewModel.kt:113-115`），没有 `previewSceneChange`。
  - 语义也不对：原型是“Gemini 改用日本节点”（只改 Gemini，AI 行 pin 变为“Gemini：东京 03”，toast“Gemini 现使用东京 03”，1054-1055）；Android 把**整个 AI 场景**（含 GPT、Claude）切走。
  - `MockFixtures.kt:203`：`it.kind == SceneKind.AI || it.kind == SceneKind.VIDEO && service in …` 运算符优先级错误，“Netflix 走日本”会命中 **AI 场景**；无服务词（“日本”）时 payload 为 `global:<id>`，`applyCommandSwitch` 直接切全局模式并改全局节点（原型全局换节点也要内联确认“出口 IP 将更改”，692/1064）。
  - IME 搜索键 `onSubmit = { suggestions.firstOrNull()?.let(onRun) }`（`CommandOverlay.kt:71-72`）执行**第一条建议，不论类型**：空输入时第一条是 `TOGGLE_CONNECTION`（`MockFixtures.kt:177-181`）→ 打开指令框按回车就**断开 VPN**；有输入时回车直接应用出口切换。
- 建议：SWITCH_NODE 卡片先调 `previewSceneChange` 渲染与首页同一个 `ExitConfirm`（抽到 `:design` 或 `ui/common`），含 from→to IP 与“X 保持不变。”；按服务粒度的改动需要契约支持 per-service exception（与 A 对齐），未就绪前 AI 场景的指令只给“在场景中查看”而不应用。回车只执行 `primary`（且仍需二次确认），从不执行 TOGGLE/SWITCH_MODE。修正 `MockFixtures.kt:203` 的括号；`global:` 指令走与全局卡相同的内联确认。

---

## 一、Design 组件（D）

### P1
**D-P1-1 `ZSheet` 没有最大高度也不可滚动，内容超出屏幕即被截掉**
- `design/.../components/ZSheet.kt:86-114`（Column 包内容，无 `heightIn(max)`、无 `verticalScroll`）；调用方 `SceneSheet.kt`、`LibrarySheet.kt`、`ActivitySheet.kt`、`TraceSheet.kt` 都没有自己加滚动
- 问题：原型 `.sheet{top:58px}` 固定高度、`.sh-body{overflow-y:auto}`（CSS 173、178）。Android 的 sheet 是 wrap-content 贴底：场景 sheet 在 fontScale ≥1.3、横屏或小屏时顶部（标题、“完成”、大数字）被推出屏幕外且无法滚动；轨迹 sheet 在 fontScale 2.0 时“始终应用”开关不可达。
- 建议：`ZSheet` 外层 `Modifier.heightIn(max = maxHeight - statusBar - 58.dp)`，标题栏固定，`content` 放进 `Column(Modifier.weight(1f, fill=false).verticalScroll(...))` 并配 `nestedScroll` 让下拉关闭只在滚到顶时生效。

**D-P1-2 触感过度：几乎每个按钮按下都震，开关关闭也用 ToggleOn**
- `ZButton.kt:43`（除 Ghost 外全部 `haptic`）、`ZChip.kt:36`、`ZSegmented.kt:54`、`ZToggle.kt:56`（开/关都 `HapticFeedbackType.ToggleOn`）、`HomeHeader.kt:134`、`SettingsScreen.kt:104`、`TodayScreen.kt:120`、`OnboardingScreen.kt:93`
- 问题：“更改/取消/应用/继续/分享/存储图像”、每个 chip、每个分段、模式菜单每项都在按下时 `ContextClick`；原型只有滑动跨格时 `navigator.vibrate(4)`（981）。而真正需要的“滑动换地区每跨一格”反而没有（`SceneCard.kt:100` 只在松手时一次）。
- 建议：`zPressable` 默认无触感，`ZButton` 去掉；只保留：连接开关（`ToggleOn/ToggleOff` 分别用）、滑动跨格 `SegmentFrequentTick`、分段/chip 选择变化（在值变化时触发，而不是按下时）、确认/撤销成功（在结果返回后 `Confirm`）。

**D-P1-3 无障碍：`ZToggle` 丢掉 contentDescription；多处触控区 < 48dp**
- `ZToggle.kt:40`（参数 `contentDescription` 声明了但从未用于 semantics）、`ZToggle.kt:50`（Regular 51×31dp，无 `minimumInteractiveComponentSize`）；`ZToast.kt:39`（“撤销”仅文字大小，约 20dp 高）；`ZSegmented.kt:39`（36dp）；`SettingsScreen.kt:101-105`（强调色 28dp）；`PageScaffold.kt:39`（返回约 38dp）
- 问题：设置/订阅/轨迹页的开关在 TalkBack 里只读“开关，已开启”，不知道是哪一项（`ZSettingsRow` 的标题与 trailing 未合并）；首页大开关传入的“连接”也丢了。tokens `touch.min-android = 48px` 与规范 §2 要求 48dp。
- 建议：`toggleable` 后加 `.semantics { contentDescription?.let { this.contentDescription = it } }`；`ZSettingsRow` 在 trailing 为开关时改为整行 `toggleable`（`Modifier.toggleable(..., role = Role.Switch)` 放在 Row 上，开关本身 `clearAndSetSemantics {}`）。所有可点小控件用 `Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)` 扩触控区、视觉尺寸不变。

**D-P1-4 中文大字无法呈现原型的细字重**
- `design/.../theme/ZType.kt:16, 35-38, 74-76`
- 问题：Inter 是“Latin + digits subset”，中文回落系统 CJK 字体；Android 13 及以下多数机型的 Noto Sans CJK 只有 Regular/Bold，`ExtraLight/Thin` 对“已连接”“未连接”“个可用节点”不起作用，44sp 的状态字会以常规字重出现，与原型 `.state{font:300 44px}`（67）和 xl.png / scrub.png 的细字差别很大。（需真机确认，见“未能确认”。）
- 建议：打包一份 CJK 细字重子集（只含状态/页头常用字，如 Noto Sans SC Light 子集 < 200 KB），或在 API ≥ 34 用系统可变 CJK 字体 `FontVariation.weight(300)`；最低限度把 `status` 改为 `Light(300)` 与原型一致（目前是 ExtraLight 200）。

### P2
- **D-P2-1** `ZSurface.kt:29` / `ZCard.kt:23` / `ZListRow.kt:25`：Solid 一律 `surface2`。原型首页卡片 `.rows`、全局卡 `.gb`、库页分组 `.grp` 是 **s1**（101、157、514），只有 sheet 内 `.list`/`.lc` 是 s2（198、289）。深色下首页卡片偏亮（#141417 vs #0C0C0E）。圆角统一 24dp，原型 `.rows` 22 / `.list`、`.lc` 20 / `.grp` 18 / `.cf` 16。给 `ZSurface` 增加 `level`（s1/s2）与 `radius` 参数，页面按原型取值。
- **D-P2-2** `ZIndication.kt:43`：按压高光恒为白色 7.5%，浅色模式不可见；用 `screenPressed`（tokens：dark 3% 白 / light 3% 黑）。`ZPressable.kt:33` 用 `indication = null` + 整体缩放 0.97，满宽列表行（首页场景行、订阅行、活动行）点下去整行缩小，原型是 `.row:active{background:rgba(255,255,255,.025)}`（104）；行级用背景高亮，缩放只留给按钮。
- **D-P2-3** `ZSheet.kt:66`：遮罩用 `colors.scrim = screenCmdBg`（`ZColors.kt:75`），浅色是 rgba(242,242,247,.8) **乳白**遮罩；原型 `.veil` 为 rgba(0,0,0,.5)、浅色再 ×0.6（171、24）。缺 `border-top:1px solid var(--hl2)`（173）。标题 `headline` 600，原型 `.sh-top h2` 500（177）。
- **D-P2-4** `ZButton.kt:29-44`：最小高 52dp、15/600；原型 `.btn` 40px、14/500（135）；Secondary 是 s3 + 描边，原型 `.btn.q` 为 `--hl` 底无描边（138）。视觉高保持 40，用 `sizeIn(minHeight=48)` 扩触控区。
- **D-P2-5** `ZChip.kt:28, 31, 40`：40dp 高、15sp、未选中字色 t1；原型 `.chip` 30px、13px、t2（465）。
- **D-P2-6** `ZSegmented.kt:35-46`：外圆角 10（原型 13）、滑块无阴影（原型 `0 2px 6px rgba(0,0,0,.4)`，189）、字号 13（原型 13.5）、`bouncy` 弹簧（原型 .32s `--e`）。
- **D-P2-7** `ZSearchField.kt:39-58`：48dp/圆角 16，原型 `.fs` 40/12（457）；占位符是兄弟 `ZText`，输入后字段在 TalkBack 中无名称——给 `BasicTextField` 加 `semantics { contentDescription = placeholder }`；String 版 API 会把拼音组合中的字母回传给 `onValueChange`（见 H-P2-12、L-P2-5），改用 `TextFieldState` 并在 `composition != null` 时跳过查询。
- **D-P2-8** `ZRegionBadge.kt:22-27`：12sp 常规、圆角 10、minWidth 32；原型 `.cc` 600 10.5px、圆角 5、min 28、高 20（110），scene.png/scrub.png 的徽标明显更小更方。
- **D-P2-9** `ZType.kt:74-85`：tracking/字重与原型不符——status −0.01em（原型 −0.035，67）、hero −0.02em（原型 −0.045，85）、display 88 Thin（原型 `.cbig` 84/200/−0.06，385）、number Light 300（原型 `.lc b` 200/−0.03，290）、sectionLabel 14sp（原型 `.sec` 13，98）。
- **D-P2-10** `ZProgressBar.kt:28-30`：3dp、底色 s4；原型 `.bar` 2px、底色 `--hl`（143）。
- **D-P2-11** `ZTrafficStat.kt:34, 39`：单位“MB/s”17sp、上行 17sp；原型 `.spd span` 13 t3、`.spd2` 13（86-87）。`:47-60` 每个字符一个 `AnimatedContent`，1 Hz 刷新时每秒创建多组动画，改为整串 `AnimatedContent` 或仅变化位滚动且 key 按位。
- **D-P2-12** 文案全部硬编码在 Kotlin（如 `HomeHeader.kt:91-95`、`SceneCard.kt:73`），而 `res/values-en/strings.xml` 与 `localeFilters += "en"`（`app/build.gradle.kts:33`）声明了英文——英文系统下界面仍是中文、App 语言设置无效。要么移到 `strings.xml`，要么去掉 en 声明。

---

## 二、Home + Scene + Command + Activity + Today（H）

### P1
**H-P1-1 撤销吐司与故障切换提示被 sheet 盖住，离开首页就丢失**
- `HomeScreen.kt:149-155`（`ZToast` 在 HomeContent 内）；`AppRoot.kt:79-143`（所有 sheet / 指令层画在 NavHost 之上）；`HomeViewModel.kt:60-64, 119-127`
- 问题：`core.failovers` 发出的“AI 出口无响应，出口 IP 不会自动更换”/“视频出口已自动切换到 X · 撤销”在任意 sheet 打开时画在遮罩下面；用户在节点/规则/订阅页时 Home 不在组合中，4 s 后吐司过期，**永远看不到**。这正是 commit `2f595c9` 承诺给用户的安全提示。
- 建议：把 Toast 宿主上移到 `AppRoot` 的 Box 最顶层（在 CommandOverlay 之后），由一个应用级 `ToastController`（`AppGraph` 持有的 `SharedFlow`）驱动；故障提示在非首页也显示。

**H-P1-2 引擎异常无任何错误呈现，部分路径会直接崩溃**
- `HomeViewModel.kt:83-106, 108-117`（`viewModelScope.launch` 内无 try）；`CoreEngine.kt` 的 `applySceneChange` 会经 `reloadIfRunning` 抛 `ZephyrException(CORE_CRASHED)`；`ImportSheet.kt:49-50` 只捕获 `ZephyrException`
- 问题：确认更改 / 撤销 / 指令应用时核心报错 → 未捕获异常 → 进程崩溃；而其它页面（`TraceSheet.kt:74`、`SubscriptionsScreen.kt:124`、`MainActivity.kt:50`）则 `runCatching` 静默吞掉，用户点了没反应。全 App 没有一个错误横幅/吐司。
- 建议：VM 用统一 `launchCatching { }` 把 `ZephyrException` 映射成吐司（带“重试”），其余 `Throwable` 记录日志；导入、覆写、更新失败都要有可见反馈。

**H-P1-3 场景行“滑动换地区”交互与原型不一致**
- `SceneCard.kt:91-105`、`HomeViewModel.kt:83-90, 131`
- 问题：原型是“擦洗”（scrub）：拖动中每 42px 跨一格，徽标与节点名实时变化、`.cc.tick` 放大变蓝、底部 `.track` 显示 5 个格位、每跨一格震一下，松手才出确认（978-988；CSS 111、116-121）。Android 是“甩一下 > 60dp 才换一格”，拖动过程中行没有任何视觉变化，地区表是写死的 `listOf("SG","JP","US","HK","TW","KR")` 并且循环（原型到头即止），该地区无候选时 `return@launch` 静默无反应。
- 建议：拖动时按 `dx / 42.dp` 实时计算 index，就地渲染候选（先 `sceneCandidates` 预取各地区首选），显示 track 与 tick 动画，每跨一格 `SegmentFrequentTick`，松手再 `previewSceneChange`；地区列表来自引擎（场景池的地区），不循环；无候选的格位置灰。

**H-P1-4 场景行不支持大字体堆叠（原型 19，xl.png）**
- `SceneCard.kt:117-148`（注释写明“40/60 一行，长名截断”）
- 问题：原型 `.device.xl .row{flex-direction:column}`、名称 22 / 元信息 16 / 节点 19，并左对齐（418-422）。现在 fontScale 1.5–2.0 下右栏 60% 宽内节点名与“Claude：US-Fixed-01”被截成“Cl…”，正是锁定说明这类关键信息。
- 建议：`LocalDensity.current.fontScale >= 1.3f`（或测得放不下时用 `SubcomposeLayout`/`FlowRow`）切换为纵向：名称 → 可用数 → [徽标] 节点 → 锁定说明，全部 `maxLines = 2`。

**H-P1-5 首页每秒整页重组，VM 循环不随生命周期暂停**
- `HomeViewModel.kt:37-45, 48-50, 67, 68-77`；`HomeScreen.kt:96-131`
- 问题：`now`（1 Hz）、`traffic`、`spark`、`pending`、`toast` 都在同一个 `HomeUi` 里，LazyColumn 的每个 item lambda 都捕获 `ui`，所以每秒（以及每个流量样本）status / traffic / scenes-h / scenes / subs-h / subs 全部重组；`(u.spark + x).takeLast(90)` 每秒分配两份列表。`stateIn(SharingStarted.Eagerly)` + `while(true){ delay(1000) }` + `engine.traffic().collect` 在 App 退到后台后仍持续运行（VM 活着就跑），真实核心下 `traffic()` 每秒走一次 FFI。
- 建议：拆成独立 `StateFlow`（`clock`、`traffic`、`spark`、`sceneUi`），时长用 `Text` 只订阅 clock，或直接用 `SystemClock` + `produceState` 局部刷新；流量/时钟改为 `SharingStarted.WhileSubscribed(5_000)`，UI 侧已用 `collectAsStateWithLifecycle`，后台即停。spark 用环形 `FloatArray` + 版本号。

**H-P1-6 常驻组合的 sheet 在隐藏、甚至后台时仍在收集/轮询**
- `AppRoot.kt:116-130`（所有 sheet 恒在组合中，只靠 `visible` 控制动画）；`ActivitySheet.kt:31-32`；`TraceSheet.kt:49`；`LibrarySheet.kt:32-36`
- 问题：`ActivitySheet` 的 `recentHosts(5).collectAsState` 永远在跑，真实核心下 `CoreEngine.kt:415-422` 每秒轮询一次 mihomo REST；`collectAsState` 不感知生命周期，屏幕关闭/退后台也继续。`TraceSheet`、`LibrarySheet` 各自再收集一份 `scenes()`（每个收集者每 5 s 各走一次 FFI，`CoreEngine.kt:272-279`）。反过来 `LibrarySheet` 的 `produceState` 只在首组合时取一次 → 导入订阅后数字不更新。
- 建议：sheet 内容只在 `visible` 时组合（`if (visible)` 包住收集，或把 `AnimatedVisibility` 内部作为收集作用域）；统一改 `collectAsStateWithLifecycle`；Library 计数用 `LaunchedEffect(visible)` 在每次打开时刷新。

**H-P1-7 全局模式卡写死“东京 03”，“更换节点”跳到无法选择节点的节点页**
- `HomeScreen.kt:121`（`GlobalModeCard("东京 03", …)`）、`HomeCards.kt:28-38`、`AppRoot.kt:98`
- 问题：无论实际全局节点是什么都显示“所有流量均经由东京 03”；“更换节点”导航到节点库，而节点行不可点选（`NodeRows.kt:32-47` 无 click）——死路。原型是卡内展开 `.gcf`：`出口 IP 将更改 JP 203.0.113.61 → SG 198.51.100.7` / `所有 App 的出口都将变为新加坡 02。` / [更改为新加坡 02][取消]，确认后吐司“已切换至新加坡 02”+撤销（692、1064-1065）。
- 建议：节点名取 `ConnectionState`/全局组的当前节点；“更换节点”展开内联候选 + 确认（复用 ExitConfirm），不跳页。

**H-P1-8 场景 sheet：漏斗数字是编造的，缺“订阅分组 / Zephyr 优选”分段与候选列表，三行均为死路**
- `SceneSheet.kt:36, 39, 56-59`
- 问题：`"检测自 2 个订阅中的 512 个节点"` 与漏斗 `512 / 138 / 27 / s.available+3` 全部写死或凭空计算，且标签错位（“全部”对 138、“延迟低于 300 ms”对 27，原型是 512 全部 / 138 / 27 / 9，812-815）。缺原型 `srcSeg` 分段（810）与按延迟排序的候选列表（scene.png，`poolList`）；“节点不可用时 / Claude（固定）/ 检测频率”三行有 chevron 与按压效果，`onClick = {}`。
- 建议：数字来自契约（若缺字段，请 A 增加 `Scene.funnel` / `poolSize` / `sourceCount`，未就绪前隐藏漏斗而不是编造）；补分段与候选列表（点选候选走 ExitConfirm）；未实现的行去掉 chevron 与点击，改为纯展示值。

**H-P1-9 指令解析标签按位置硬套，输入框没有 token 下划线**
- `CommandOverlay.kt:108-121`；原型 `parse()`/`mirror()`（1022-1029）、CSS `.tk.s/.r/.a`（225-228）
- 问题：`Tokens` 用空格/“走”/“用”切分后依次标成“服务 / 地区 / 范围”：“GitHub 直连”→ 地区=直连，“视频只用 4K 节点”→ 服务=视频只、地区=4K 节点。原型标签来自解析结果（服务/场景/地区/操作/范围），并在输入文字下画蓝/绿/琥珀下划线。
- 建议：让 `commandSuggestions` 返回解析 span（契约增加 `tokens: [{start,len,kind,label,value}]`），据此渲染 chips 与 `AnnotatedString` 下划线（`VisualTransformation` 实现，组合输入期间不变换）。

**H-P1-10 今日卡：深色主题下“晨/雾”配色的品牌标看不见；PNG 编码在主线程**
- `TodayScreen.kt:109`（`ZTheme.run { ZephyrLockup() }` 并未改色）、`ZephyrLockup.kt:26-28`（恒用 `ZTheme.colors.text1`）；`TodayScreen.kt:131-132, 173-189`
- 问题：深色主题 + 晨/雾卡片 → 白色 Zephyr 标识画在 #F1ECE6/#E6ECF4 上，几乎不可见（原型 `.card[data-pal=dawn] *{color:#16181c}`，429）。分享/存储时 `bmp.compress(PNG, 100)` 在主线程（`scope` 为 Main），~1000×1500 位图编码 100–300 ms 级，按钮按下即卡顿。
- 建议：`ZephyrLockup(tint: Color = …)`，卡片内传 `style.fg`；编码与写盘放 `withContext(Dispatchers.IO)`，完成后给吐司“已存储到 图片/Zephyr”。

**H-P1-11 确认更改后的吐司文案与原型不符**
- `HomeViewModel.kt:97`（`"已换到 ${p.node.name}"`）、`:111, :115`
- 问题：原型确认后是 `已切换至${REG[pend].n}` + 撤销（992），全局换节点同为“已切换至新加坡 02”（1065），指令应用是“Gemini 现使用东京 03”（1055）。现在三条路径都是“已换到 X”。（tokens 注释里的“已换到 东京 03”是旧稿，以交互脚本为准。）
- 建议：场景/全局确认用“已切换至X”，指令用“{服务} 现使用{节点}”/“{服务} 现为直连”。

**H-P1-12 原型 10“检测中”、11“服务不可用”无法表达**
- `core-engine/.../Model.kt:92-102`（`Scene` 无按服务健康、无检测进度）、`SceneCard.kt:121-126, 141`
- 问题：scan 需要“正在检测 138/512”+ 行内蓝色进度条（1327）；zero 需要左侧红字“Claude 不可用”、右侧“GPT、Gemini 正常”（1328，zero.png）。现在只能显示“N 个可用”。
- 建议：与 iOS H-P1-5 同一契约缺口，请 A 给 `Scene` 增加 `services: [ServiceHealth]` 与 `scan: ScanProgress?`；合入前在 NOTES 记缺口。

### P2
- **H-P2-1** `HomeHeader.kt:92`：“正在连接”，原型“连接中”（920）。`:104-112` 模式与时长 17sp，原型 `.sub` 14px、时长 t3（70-73）；`:118-149` 模式是弹出菜单，原型点一下在 规则→全局→直连 间循环（939）——如保留菜单，请与设计确认并在 NOTES 说明。
- **H-P2-2** `HomeScreen.kt:112`：未连接时只是 150dp 空白；原型保留虚线基线 + `.idle` 文案（90-91、969，home-off.png）。
- **H-P2-3** `HomeScreen.kt:108-109`：只有数字可点开“最近连接”，曲线不可点（原型整个 `.wind` 是按钮，975）；`ZSparkline` 1 Hz 跳变，原型 120 ms 平移 + 头部圆点（955-971）。可用 `withFrameNanos` 在两次样本间插值，**只在可见且未被 sheet 覆盖时**运行。
- **H-P2-4** `SceneCard.kt:114-146`：名称 18.7sp（headline×1.1）/元信息 15/节点 17/锁定说明 15，原型 17/13/15/12（106-112）；行内边距 18/18，原型 15/16（102）；锁图标未加 0.85 透明度（113）。
- **H-P2-5** `SceneCard.kt:65-77`：教学提示是独立一行，撑高卡片；原型 `.coach` 浮在分隔线上并左右轻推（122）。`hinted` 用 `remember`，每次回到首页都重新出现，应持久化到 DataStore。`:68` 提示显示时会去掉 AI 行后的分隔线，且提示消失后分隔线也不回来。
- **H-P2-6** `SceneCard.kt:157-183`：确认卡底色 `surface3 × 0.5` + `hairlineStrong` 描边，原型实色 s3 + `--hl`（129）；标题 16sp（原型 14，131）、内边距 16（原型 14）、按钮 52dp（原型 40）；IP 行单色 t2，原型箭头 t4、目标 IP t1（674）。`:169` affectedApps 为空时回落“更改 AI 的出口 IP？”，建议此时也列出受影响服务或至少写“更改 AI 场景的出口 IP？”。
- **H-P2-7** `HomeCards.kt:46-63` + `ZFormat.kt:61-69`：首页 7 天内到期应显示星期（原型“周一到期”，698），现为“2 天后到期”；订阅名 17（原型 16）、剩余量 17（原型 15）、到期 13（原型 12）；只显示前 3 个，无“更多”。
- **H-P2-8** `HomeScreen.kt:117`：`ago()` 返回“刚刚”时 `replace("前","前检测")` 不生效，显示“刚刚”而不是“刚刚检测”。
- **H-P2-9** `ActivitySheet.kt:34`：标题“刚才”，原型“最近连接”（830）；`:49` 副标题分隔符“，”，原型“AI · US-Fixed-01”（834）。`AppRoot.kt:127-128` 轨迹作为第二张 sheet 叠在活动 sheet 上（双重遮罩），原型在同一张 sheet 内切换内容（1005）。
- **H-P2-10** `TraceSheet.kt:56`：域名用 hero ExtraLight ~45sp，原型 300 32px（843）；`:93` 节点圆点 14dp（原型 11）；缺流光与逐步出现动画（256-258、1006）；`:74` 覆写失败被吞掉。
- **H-P2-11** `CommandOverlay.kt:63`：遮罩 `bg × 0.86` 无模糊，原型 `--cmdbg` .72 + blur 30（212），API 31+ 可用 `RenderEffect`；输入框 48dp/圆角 16，原型 `.cin` 56/28 + `--hl2` 描边（214）；无结果时空白，原型“无结果”（1051）；遮罩用 `zPressable`，按下整个遮罩缩放 0.97。`AppRoot.kt:139-140` 解析副标题里的“将使用 ”拿节点名，`it[1].toLong()` 对异常 payload 会崩。
- **H-P2-12** `CommandOverlay.kt:57-61`：40 ms 去抖但拼音组合期间按字母请求建议；同 D-P2-7 处理组合态。
- **H-P2-13** `TodayScreen.kt:82`：页面底色跟随主题（浅色下为灰白），原型今日页恒为 #000（381）；`:67-71` 三套配色与原型 #02040a / #F6EEE6 / #ECEDEF（382、427）不符；数字 88 Thin（原型 84/200，385）、单位 22（原型 18）；流线静态，原型缓慢流动（1079，可选）。
- **H-P2-14** 撤销窗口：tokens `motion.undo-window = 4s`，原型脚本 5 s 且有 2px 蓝色倒计时条（162-168、993）。与设计确认取值，并补倒计时条；TalkBack 开启时用 `AccessibilityManager.getRecommendedTimeoutMillis()` 延长。
- **H-P2-15** `HomeCards.kt:30-37`：全局卡“使用规则模式 / 更换节点”按钮 52dp、文案 headline，原型 `.gb .h` 15 / `.k` 13（158-159）。

---

## 三、Library + Nodes + Rules + Subs + Settings + Onboarding（L）

### P1
**L-P1-1 从资料库进入的页面返回到首页，返回标签与实际去向不符**
- `AppRoot.kt:116-124`（先 `library = false` 再 navigate）、`NodesScreen.kt:86`、`RulesScreen.kt:60`、`SubscriptionsScreen.kt:59`（返回标签恒为“资料库”）
- 问题：原型 `[data-back]` → `show('home'); sheet('libSheet')`（1287），即返回后资料库重新打开。现在返回落在首页、资料库已关。反过来从首页全局卡/指令进入节点或规则页（`AppRoot.kt:98, 133-134`）时左上仍写“‹ 资料库”，点了却回到首页。（设置页已按来源传入“首页/资料库”，做法正确。）
- 建议：`Nodes/Rules/Subs` 路由像 `SettingsRoute` 一样带 `back` 与 `fromLibrary`；`onBack` 时 `popBackStack()` 后若 `fromLibrary` 则 `library = true`。

**L-P1-2 引导页：三个导入入口是死路，“先看看示例”只是假文案，“简单/优选”选择被丢弃**
- `OnboardingScreen.kt:63-66, 50, 81, 59`
- 问题：扫描二维码 / 从电脑导入 / 从文件导入 `onClick = {}`；“先看看示例”只把文案设为“Nebula Cloud（312 个节点）”就进入第 2 步，**什么也没导入**，release 下完成引导后首页是空的；第 2 步选中的 `mode` 从未写入设置（`继续` 只 `setOnboarded()`）；粘贴链接失败被 `runCatching` 吞掉，无加载态、无错误提示。
- 建议：入口与 `ImportSheet` 共用实现（扫码用 CameraX/ML Kit 或 GMS Code Scanner；文件用 `ActivityResultContracts.OpenDocument`）；示例数据只在 debug 出现或真正导入示例订阅；`继续` 时把选择写进 `Settings`（场景来源：订阅分组 / Zephyr 优选）；导入中显示“正在添加…”，失败显示“这不是有效的订阅链接”。

**L-P1-3 多处“看得见点不动”的死路入口**
- `SubscriptionsScreen.kt:110`（“其他 212 个 ›” `onClick = {}`）、`SettingsScreen.kt:63`（“受信任的 Wi‑Fi ›” `onClick = {}`）、`AppRoot.kt:123`（资料库的“小组件与快捷开关 / 受信任的 Wi‑Fi / 本地代理端口”全部跳设置首页）、`ImportSheet.kt:67-69`（扫码/电脑/文件三项点了以**红色错误样式**提示“将在核心接入后启用”）、`SceneSheet.kt:56-59`（见 H-P1-8）
- 建议：未实现的入口不显示 chevron、不可点；或在本版本隐藏。资料库三行直达对应子页（受信任 Wi‑Fi 列表、本地代理设置、小组件说明页）。

**L-P1-4 节点页写死演示数据**
- `NodesScreen.kt:60`（`CHIPS` 写死 US 3,118,402 / JP 2,204,117…）、`:93`（“来自 214 个订阅”写死）、`:102`
- 问题：用户只有一个订阅时也显示“US 312 万”“来自 214 个订阅”；点 chip 得到 0 条结果。
- 建议：chips 由 `nodeIndex().sections`（按 count 降序取前 8）生成；副标题用 `subscriptionsSummary().count`。

**L-P1-5 强调色选择器无障碍不可用**
- `SettingsScreen.kt:98-106`
- 问题：28dp 圆点（< 48dp）；TalkBack 读英文枚举名“BLUE/PINK”；选中态没有 `selected` 语义；整行不是单选组。
- 建议：每个圆点 `sizeIn(48.dp)` 触控区、`semantics { contentDescription = "蓝色"; selected = …; role = Role.RadioButton }`，外层 `selectableGroup()`。

### P2
- **L-P2-1** `ZStatTile.kt:15-20` / `LibrarySheet.kt:38-46`：原型 `.lc` 固定 110 高、数字在顶说明在底（space-between）、数字 200 30px、说明 14px、圆角 20、间距 10（288-291）；现为自然高度、Light 300、说明 15sp、圆角 24、间距 12。fontScale 2.0 下“1,311 万”在 `maxLines = 1` 下被截成“1,…”。
- **L-P2-2** `LibrarySheet.kt:32-34`：计数只在首组合取一次（同 H-P1-6），导入/更新后不刷新。`:49` 文案“小组件与快捷开关”，原型“小组件与控制中心”（Android 可保留，但应有对应页面）。
- **L-P2-3** `NodeRows.kt:34-44`：行高恒 52dp；原型 xl 66、隐藏协议列、名称 19（550）。`ZTheme.kt:35` 定义了 `rowHeightLarge = 66.dp` 但未使用。
- **L-P2-4** `NodesViewModel.kt:74-85`：chip 立即查询与去抖查询并发，`run()` 不取消前一次，后发先至时结果可能回退；改为单一 `collectLatest`，chip 走 `queryFlow` 并跳过去抖。`NodesScreen.kt:101-102` chip 选择即把代码写进搜索框做文本搜索（同 iOS L-P2-9），应走地区过滤。
- **L-P2-5** `NodesScreen.kt:95` + `ZSearchField`：拼音组合期间按字母查询，常闪“无结果”；组合态跳过。
- **L-P2-6** `NodesViewModel.kt:107-122` 在组合期间被 `NodesScreen.kt:122` 调用并启动协程、修改 `HashSet`——组合中的副作用；改为在 `LaunchedEffect(visibleRange)` 里预取页。`contentType` lambda 每项再调一次 `rowAt`（含 `subList.sumOf`），可缓存区段前缀和。
- **L-P2-7** `NodesScreen.kt:97`：“N 个 · 0.04 ms”放在搜索框下方，原型在框内右侧 `.fs .tm`（460）；`:149` 吸顶头实色底，原型 86% 底 + 模糊（485）；`:192-201` 气泡只显示总数，原型“1,204 / 2,204,117”（1214）；索引条无无障碍语义。
- **L-P2-8** `RulesScreen.kt`：缺原型右上“+”（729）。Android 没有出现 iOS 那种不可提交的表单（未构成死路），但覆写目前只能从轨迹页添加，需在 NOTES 说明或补入口。`:69` 搜索框在卡片外，原型在 `.rt` 卡片内与匹配链一体（499-501）；`:139-153` 链路节点全为实心蓝点、无竖线，原型空心点 + 竖线、末项实心蓝（503-506）；`:110` 层类型标签为填充底，原型 1px 描边 10px mono（522）；命中行 16% 蓝，原型 9%（524）；占位“输入域名或 IP”，原型“测试域名或 IP”（733）。
- **L-P2-9** `SubscriptionsScreen.kt:56`：`now = remember { clock() }` 冻结，页面停留期间“2 小时前”“26 天后到期”不变；`:115-118` “自动更新 ›”点一下在 6/12/24 循环（有 chevron 却不进入页面）；`:134` 增减数字 30sp Light，原型 `.diff .rw b` 300 22px（539）；规范 §4 的“左滑更新/删除”未实现，单个订阅无法更新或删除。
- **L-P2-10** `SettingsScreen.kt:91-93`：“外观 ›”点一下循环；缺原型“应用图标 · 深色”（791）；`:65-69` “本地代理端口 ›”点一下直接开关；`:75-77` “结果保留”同样循环。
- **L-P2-11** `OnboardingScreen.kt:52-100`：无品牌标（原型 `.obmk`，581）；标题 `title` 30/600，原型 `.ob h1` 300 34/1.18 −0.03em（266）；选项卡无单选圆点 `.rd`、选中无 7% 蓝底（268-271）、底色 s2（原型 s1）；选项没有 `Role.RadioButton/selected` 语义；第 2 步按返回直接退出 App；状态用 `remember`，旋转后回到第 1 步。
- **L-P2-12** `AppRoot.kt:129`：`ImportSheet` 的 `onDone("已添加 … 个节点")` 被忽略，导入成功没有任何反馈。
- **L-P2-13** `PageScaffold.kt:37`：只处理 `statusBars`，横屏/挖孔屏的 `displayCutout` 水平内边距未处理。

---

## 四、通知 / 快捷设置磁贴 / 小组件（W）

### P1
**W-P1-1 小组件显示的速率是连接那一刻的快照，模式写死“规则”，点任意处即断开**
- `ZephyrWidget.kt:56-60, 74, 84`；`ZephyrVpnService.kt:76, 96`（只在连上/断开时 `refreshAll`）；`res/xml/zephyr_widget_info.xml`（`updatePeriodMillis="0"`）
- 问题：连接时取一次 `recentTraffic(1)`，此后数小时都显示同一个“2.8 MB/s”（且在 release 下是 P0-1 的 mock 值）；`"$du/s · 规则"` 不论全局/直连都写“规则”；整个小组件 `clickable(ToggleAction)`，用户想点开 App 却把 VPN 关了。原型 hs.png：独立 36px 电源按钮（`.pw`），其余区域打开 App。
- 建议：主数字改为不随秒变化的信息（“已连接 · 规则 · 东京 03”或今日用量），或在服务里按 ≥ 30 s 节流 `updateAll` 并标注“x 分钟前”；模式取 `ConnectionState.mode`；整卡点击 `actionStartActivity<MainActivity>()`，仅电源按钮 `actionRunCallback<ToggleAction>()`。

**W-P1-2 从不申请 POST_NOTIFICATIONS：Android 13+ 看不到原型 17 的常驻通知，也不会有到期提醒**
- `AndroidManifest.xml:9`（只声明）；全仓无 `requestPermission(POST_NOTIFICATIONS)`；`Notifications.kt:77-83` 的 `expiry()` 无调用方
- 问题：targetSdk 36 下未授权时，前台服务通知不出现在通知栏（只在任务管理器里），“Zephyr · 2:14:07 / 2.8 MB/s ↓ · 194 KB/s ↑ / 断开连接 · 全局模式”（and.png）整块缺失；“Orbit 将于 11月9日 到期 · 剩余 12.0 GB”从未发送。
- 建议：首次成功连接后（不是启动时）用 `ActivityResultContracts.RequestPermission` 申请，配一句说明“用于显示连接状态与订阅到期提醒”；拒绝后在设置里给入口。`SubscriptionWorker` 检测 ≤ 3 天到期时调用 `Notifications.expiry`。

**W-P1-3 快捷设置磁贴在 API 28–33 会崩溃**
- `ZephyrTileService.kt:36`（`Tile.subtitle` 为 API 29）、`:52-57`（`startActivityAndCollapse(PendingIntent)` 为 API 34）；`app/build.gradle.kts:13`（`minSdk = 28`）
- 问题：Android 9 上磁贴一开始监听即 `NoSuchMethodError`；Android 9–13 首次点磁贴（需要 VPN 授权）时调用 34 才有的重载 → 崩溃。
- 建议：`if (SDK_INT >= 29) tile.subtitle = …` 否则把状态拼进 `label`；`SDK_INT >= 34` 用 PendingIntent 重载，否则 `startActivityAndCollapse(Intent)`（加 `FLAG_ACTIVITY_NEW_TASK`）。启用 lint `NewApi` 为 fatal。

### P2
- **W-P2-1** `ZephyrVpnService.kt:66-74` / `Notifications.kt:58-66`：每个流量样本都重建并 `notify()`，息屏时也每秒一次；时长改用 `setUsesChronometer(true).setWhen(since)`，速率按 2–5 s 节流且仅在屏幕点亮时更新（`PowerManager.isInteractive`）。`:62` 全局模式显示“全局 · 所有流量经由同一节点”，应写出节点名（原型 and.png 的格式）。
- **W-P2-2** `ZephyrTileService.kt:35`：副标题取 `scenes.firstOrNull()`，全局模式下显示的是 AI 场景节点而非全局节点；`:26` `AppGraph.init` 在主线程（`Dispatchers.Main.immediate`），首次可能加载 .so。
- **W-P2-3** `ZephyrWidget.kt:73-101` 对照 hs.png：缺电源按钮、“今日 1.8 GB + 24 小时柱状图”中号组件、场景行延迟（“61 ms”）；`zephyr_widget_info.xml` 声明 `reconfigurable` 但没有 `android:configure` Activity。
- **W-P2-4** `Notifications.kt:54`：`setColor` 固定 #0A84FF，未跟随强调色（与 iOS W-P2-5 同）。

---

## 五、Android 平台（A）

### P1
**A-P1-1 状态栏/导航栏图标颜色跟随系统而不是 App 外观设置**
- `MainActivity.kt:24`（`SystemBarStyle.auto(...)` 只看系统夜间模式）、`AppRoot.kt:68`（App 内可强制深/浅）
- 问题：系统深色 + App 设为“浅色” → 白色状态栏图标落在 #F2F2F7 上看不见；反之黑图标落在纯黑上。
- 建议：在 `AppRoot` 里随 `dark` 调用 `WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !dark`（或在 `LaunchedEffect(dark)` 里重新 `enableEdgeToEdge(SystemBarStyle.dark/light)`）。

**A-P1-2 导入 sheet 被软键盘遮住**
- `ZSheet.kt:99`（只有 `navigationBarsPadding()`）、`ImportSheet.kt:55-58`
- 问题：edge-to-edge 下 `adjustResize`（Manifest:29）不再缩放内容，贴底的 sheet 不加 `imePadding()`，输入框与“添加”按钮在键盘下面。指令层已加 `imePadding`（`CommandOverlay.kt:68`），sheet 漏了。
- 建议：`ZSheet` 在 `navigationBarsPadding()` 前加 `.imePadding()`（或 `windowInsetsPadding(WindowInsets.ime.union(navigationBars))`）。

**A-P1-3 “存储图像”在 Android 9 上崩溃**
- `TodayScreen.kt:181-189`；`AndroidManifest.xml` 未声明 `WRITE_EXTERNAL_STORAGE`
- 问题：minSdk 28，API 28 上 `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` 插入需要 `WRITE_EXTERNAL_STORAGE`，否则 `SecurityException`；且未加 `IS_PENDING` 流程。
- 建议：声明 `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>` 并在 28 上运行时申请；API 29+ 用 `IS_PENDING=1` 写完再置 0；捕获异常给吐司。

**A-P1-4 深链与导出的 Activity 可被任意 App/网页静默导入订阅或启动 VPN**
- `MainActivity.kt:31, 44-53`；`AndroidManifest.xml:25-45`
- 问题：`clash://install-config?url=` / `zephyr://import?url=` 是 BROWSABLE，任意网页可让 App **无确认**导入订阅（换掉用户的出口）；导出的 `MainActivity` 接收 `ACTION_CONNECT`，任意 App 可拉起连接。`onCreate` 每次都 `handle(intent)`，旋转/进程重建会重复导入或重复连接。
- 建议：深链只预填 `ImportSheet` 并要求用户点“添加”；`ACTION_CONNECT` 改用不导出的 trampoline Activity 或校验来源（PendingIntent 只给 tile/widget）；`if (savedInstanceState == null) handle(intent)`，处理后 `setIntent(Intent())`。

### P2
- **A-P2-1** `MainActivity.kt:27`：`runBlocking` 读 DataStore 在主线程，冷启动直接加数十 ms；用 `installSplashScreen().setKeepOnScreenCondition { !ready }` 异步读取。
- **A-P2-2** `AndroidManifest.xml:50, 56-57`：前台服务类型 `specialUse` + 子类型 “vpn”，上架 Play 需提交特殊用途声明；VpnService 由系统绑定，确认是否可改为 `systemExempted`（仅限始终开启 VPN 场景）或保留 specialUse 并准备声明文案。
- **A-P2-3** `res/values/themes.xml` / `values-night/colors.xml`：启动窗口背景与 splash 跟随系统主题，App 强制外观与系统相反时会先闪一帧反色。
- **A-P2-4** `AppRoot.kt:71-76`、`OnboardingScreen.kt:47-50`：sheet 打开状态、引导步骤用 `remember`，旋转/折叠屏展开/进程重建后丢失；改 `rememberSaveable`。
- **A-P2-5** `HomeScreen.kt:97`：LazyColumn 底部 120dp 未叠加导航栏 inset，三键导航（48dp）下最后一行订阅贴在指令栏下；横屏挖孔未处理水平 inset（同 L-P2-13）。
- **A-P2-6** `ZephyrVpnService.kt:56-58`：tun 建立或核心启动失败只写 Log 然后 `stop()`，首页回到“未连接”无任何原因；应把错误写入 `ConnectionState(FAILED, error)` 并在首页显示。
- **A-P2-7** `AndroidManifest.xml:103`：`<profileable android:shell="true"/>` 进入 release，建议仅 benchmark/internal 变体。
- **A-P2-8** `ZSheet` 与 `CommandOverlay` 已接 `PredictiveBackHandler`/`BackHandler`，但 NavHost 页面之间未定义预测性返回的过渡（`AppRoot.kt:82-85` 只给了普通 enter/exit），返回手势预览时看不到上一页跟随；`navigation-compose 2.10` 可直接用 `popEnterTransition` 配合 `seekable` 过渡。

---

## 最重要的 10 条（按修复优先级）

1. **P0-1** release 经 `CoreEngine by MockEngine` 显示伪造的今日用量/流量曲线/存储/轨迹/指令，且无核心或无订阅时显示“已连接”但没有隧道（`CoreEngine.kt:75`、`TunBridge.kt:62-66`）。
2. **P0-2** 指令“Gemini 走日本”无 from→to IP 内联确认直接改整个 AI 场景出口；“Netflix 走日本”误改 AI；空输入按回车会断开 VPN（`CommandOverlay.kt:71-86`、`MockFixtures.kt:203`）。
3. **W-P1-3** QS 磁贴在 API 28–33 崩溃（`Tile.subtitle` API 29、`startActivityAndCollapse(PendingIntent)` API 34，minSdk 28）。
4. **W-P1-2** 从不申请 POST_NOTIFICATIONS：Android 13+ 看不到原型 17 的常驻通知，到期提醒从未发送。
5. **H-P1-1 / H-P1-2** 故障切换与撤销吐司被 sheet 盖住、离开首页即丢失；引擎异常要么让 App 崩溃，要么被静默吞掉。
6. **H-P1-7 / H-P1-8 / L-P1-3 / L-P1-4** 写死的演示数据与死路：全局卡永远“东京 03”且“更换节点”无法选择；场景 sheet 漏斗数字编造、三行点不动；节点 chips 写死数字；多处 chevron 行 `onClick = {}`。
7. **H-P1-3 / H-P1-4** 场景行：滑动换地区不是原型的实时擦洗（无 track/tick/逐格触感、地区表写死并循环）；大字体不堆叠，锁定说明被截断。
8. **H-P1-5 / H-P1-6** 首页每秒整页重组、VM 循环后台不停；隐藏的活动 sheet 每秒轮询 mihomo，后台也在跑。
9. **L-P1-2** 引导页三个导入入口点不动，“先看看示例”不导入任何数据，“简单/优选”选择被丢弃。
10. **D-P1-1 / D-P1-3 / A-P1-1** `ZSheet` 无滚动（大字体/横屏内容被截）；开关无名称、多个控件触控区 < 48dp；状态栏图标不跟随 App 外观。

## 未能确认 / 需要后续验证
- 未运行 Gradle/Paparazzi，**没有发现确定的编译错误**；W-P1-3 的两个 API 级别问题若 lint `NewApi` 在 CI 中为 error 会被拦下，但当前构建配置里未见 `lint { fatal += "NewApi" }`，需看 CI 日志确认。
- D-P1-4（中文细字重回落）依赖设备系统字体：Android 14+ 的可变 Noto Sans CJK 可能支持 300，Android 13 及以下大概率只有 Regular/Bold，需在两类真机上截图对比 xl.png / scrub.png。
- H-P1-5 / H-P1-6 的重组与轮询开销需用 Layout Inspector 重组计数与 Perfetto（后台 CPU 唤醒）复核量级。
- A-P2-2：VpnService 的前台服务类型选择（specialUse vs systemExempted）以当期 Play 政策为准，需产品/上架负责人确认。
- 撤销窗口 4 s（tokens）与原型脚本 5 s（993）冲突，H-P2-14 需设计定夺。
- 原型首页模式按钮是点按循环（939），Android 做成了弹出菜单（`HomeHeader.kt:118-149`）；是否属于“平台习惯”的合理偏离，需设计确认（列为 H-P2-1，不计入 P1）。
- `core-mobile/bindings/kotlin` 与 `.so` 未在本次审查中加载，`CoreEngine` 真实路径的行为（如 `reloadIfRunning` 抛错频率）仅按代码推断。
