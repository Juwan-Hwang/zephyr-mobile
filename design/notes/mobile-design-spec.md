# Zephyr 移动端设计规范 v0.2（2026-11-06 草案；2026-11-21 补 §9 设计评审规则）

原则：保留桌面端的气质，移动端 UI 和 UX 全部重写。原生 SwiftUI + Compose。token 只认主仓库 Zephyr main 的 `packages/tokens`。

## 1. 从桌面继承的气质
- **深色优先的玻璃质感**：深色是默认（`value`），浅色是覆盖层（`lightValue`）；层次靠半透明表面和 1px 细边框分出来，不靠重阴影。
- **克制的强调色**：Apple 系统色，blue `#007AFF`（默认）/ green / orange / pink。紫色已经在主仓库里去掉了（#1624），zephyr-mobile 安卓端还默认用紫色，这就是分叉的例子。
- **文字层级用透明度表达**：primary 95%、secondary 60%、tertiary 50–56%（为过 WCAG AA 从 40% 上调，见 `tokens/README.md`）；t4 只作装饰（§9.1）。
- **大数字用细字重**：速率、延迟这类数据用 ExtraLight/Light 加等宽数字，标题用 SemiBold。
- **运动曲线**：micro 120ms、standard 200ms ease-out，slow 和 page 320ms spring `cubic-bezier(0.16,1,0.3,1)`。
- **语义色**：下载 `#0A84FF`、上传 `#FF6B6B`，success / warning / danger / info 沿用主仓库。

## 2. token 策略（单一来源）
- 只用主仓库 `packages/tokens/src/{primitive,semantic,component}.json`，不再拷贝。
- 新增 `packages/tokens/src/mobile.json` 作为移动端增补层，只放手机特有的值，不改桌面已有的值：
  - 触控目标：iOS 44pt、Android 48dp
  - 移动端字阶：桌面按钮是 10px 全大写，手机上太小，改成 13–15pt
  - 列表行高、底栏高度、安全区留白
- `config.js` 已经有 `compose` 和 `ios_swift` 两个平台，只需要把 buildPath 改到 monorepo 的 `apps/android`、`apps/ios`。
- 生成产物要有 light/dark 动态色：iOS 用 Asset Catalog 或动态 UIColor，Android 用 ColorScheme 映射，组件里不写三元判断。

## 3. 信息架构（v1 已实现：首页 + 资料库 sheet + 指令栏）
> 2026-11-18 更新（审计 U34）：原草案的「4 Tab（首页 / 代理 / 配置 / 设置）」已作废。两端都按原型 `design/prototype/`（`index.html` 25 章）实现成**单一首页 + 资料库 sheet + 底部指令栏**，没有底部 Tab。视觉与交互仍以原型为准，本节只记结构。

| 入口 | 内容 | 来自桌面 |
|---|---|---|
| **首页**（唯一主页面） | 状态大字 + 连接开关、模式菜单（规则 / 全局 / 直连）、连接时长、实时上下行（细字大数字 + 曲线）、场景卡（左右滑切换地区）、订阅卡；底部指令栏 + 资料库按钮 | home、connections（摘要） |
| 场景 sheet | 点场景卡打开：大数字、订阅分组 / Zephyr 优选分段、节点漏斗、候选列表；节点由场景按延迟自动选出 | proxies（取代策略组） |
| 指令 | 底部指令栏展开为全屏，解析成 token，预览后“应用”（契约 §15.b） | 无（移动端新增） |
| 最近连接 sheet → 连接轨迹 | 规则 → 场景 → 节点 → 出口；本次覆写 / 始终应用 | connections |
| **资料库 sheet** | 2×2 统计入口：节点、订阅、规则、场景；下方：小组件与控制中心（Android 为快速设置磁贴）、受信任 Wi‑Fi、本地代理端口、设置 | subscriptions、rule-library、proxies（节点浏览） |
| 节点页 | 虚拟列表（1e7–1e8 行）、地区索引条、搜索、可见行测延迟；**只浏览和测速，不手动选节点** | proxies |
| 规则 / 订阅 / 设置页 | 规则测试与命中链；订阅总数、更新 diff、流量卡；设置分 连接 / 检测 / 存储 / 外观 组，日志在设置内 | advanced、subscriptions、settings、logs |
| 今日卡 | 生成式纹理卡片，可分享 / 存图 | 无（移动端新增） |

- 桌面的控制台（console）手机端不做。

**不进 v1 的原草案项**（两端均未实现，审计 U34）：
- ~~策略组页（策略组卡片列表 → 节点列表）~~：由场景 sheet 取代，v1 不做。
- ~~“隐藏超时节点”开关~~：v1 不做（节点页按延迟着色，场景漏斗单独统计可连通数）。
- ~~“点一下切换节点”~~：v1 不做，出口节点由场景自动选择；单次改道走指令或连接轨迹里的覆写。
- 以上若要进后续版本，需先在契约补接口，再由两端实现。

## 4. 关键页面
- **首页**：状态大字 + 连接开关（ZConnectButton），状态变化用 spring 动效加轻微光晕（accent glow）；模式菜单；实时上下行（细字大数字加迷你曲线）；场景卡与订阅卡；底部指令栏和资料库按钮。
- **场景**：sheet 内大数字、分段、漏斗和候选列表；候选按延迟排序，颜色按延迟分档。
- **节点**：只读虚拟列表，行显示国旗、名称、延迟胶囊；停止滚动后测可见行，不提供点选切换。
- **订阅**：订阅卡显示流量用量条和到期时间；“+”打开导入面板（扫码、URL、剪贴板、文件、从电脑导入）；左滑可更新或删除。
- **设置**：分组列表，iOS 是 inset grouped 风格，Android 用自绘卡片分组，两端视觉一致。

## 5. 平台习惯（保持气质一致，交互跟随平台）
| 项 | iOS | Android |
|---|---|---|
| 主导航 | 无 Tab：单一首页 + 资料库 sheet | 同左（自绘 sheet） |
| 弹层 | sheet + detents | 自绘 bottom sheet，同样的圆角和模糊 |
| 开关 | 系统 Toggle，用强调色 | 自绘 ZToggle，尺寸和动效对齐 |
| 返回 | 边缘右滑 | 系统预测性返回 |
| 快捷入口 | 控制中心控件、小组件、快捷指令 | 快速设置磁贴、小组件 |
| 触感 | UIImpactFeedback | HapticFeedback |

## 6. 组件清单（两端同名、同 API 语义）
基础：ZSurface（玻璃/实色两种）、ZCard、ZButton（primary/ghost/danger）、ZIconButton、ZToggle、ZSegmented、ZTextField、ZBadge、ZLatencyPill、ZProgressBar、ZSheet、ZToast、ZEmptyState、ZSkeleton
业务：ZConnectButton、ZTrafficStat、ZSparkline、ZNodeRow、ZGroupCard、ZProfileCard、ZFlag（复用桌面国旗字体）、ZSettingsRow
- Android 页面层禁止直接使用 Material 组件，只能用 Z 组件拼装；Material 只当底层实现。
- 每个文件一个组件，页面文件控制在 300 行以内。

## 7. 质量门槛
- 截图测试：Android 用 Paparazzi，iOS 用 swift-snapshot-testing；同一组件和页面两端截图并排评审。
- 每个组件都要有深色、浅色、4 种强调色、大字体（Dynamic Type / fontScale）的预览。
- 性能：节点列表 2000 行滚动稳定 60fps，冷启动小于 1 秒（中端安卓）。

## 8. 下一步
1. ~~用户确认 IA 和气质描述~~（IA 已按原型定为首页 + 资料库 sheet，见 §3）
2. 落地 `mobile.json` 并调整 config.js 输出路径
3. 先做组件库和首页，两端同步

## 9. 设计评审补充规则（2026-11-21，看板 #1）
来源：2026-11-21 设计评审（huashu-design 评审方法，iOS 7.1 / Android 6.9），用户确认「值得借鉴的都借鉴」。本节是三端（iOS B、Android C、鸿蒙 D）共同规则；token 名见 `tokens/README.md`，契约部分见 `contract/zephyr-engine.md` §18。

### 9.1 颜色与可读性
- **浅色模式只给数值或圆点上色**：状态色（琥珀 = 需注意，绿 = 已连接 / 增加，红 = 超时 / 失败 / 减少）只染**数值本身**或**前置圆点**，不染整行副标题。例：订阅卡「3,118 个节点 · ● 11月9日到期」只有圆点和日期是琥珀色，其余用 t3。
- 状态色作**文字**一律用 `screen.amber-text` / `green-text` / `red-text`（浅色 #B25000 / #1F7A35 / #D70015，均 ≥4.5:1；深色与原色相同）。原 `screen.amber` / `green` / `red` 只用于圆点、进度条、图标填充。
- **状态不只靠颜色**：每个状态至少同时有形状（● 圆点、✕、进度条位置）或文字（契约 §18.b 术语：较慢 / 超时 / 未测 / 即将到期 / 已过期 / 失败）。超时延迟写「超时」，不只显示红色「—」。色盲与灰度截图下必须仍能分辨。
- **t4 不承载可读信息**：`screen.t4` 只给禁用态、装饰分隔、sheet 把手。序号、未测延迟、可点行的 chevron 用 t3；未测延迟用 `latency.unknown`（= t3）显示「—」，不用「···」。
- **强调色分角色**：开关 / 进度 / 光晕用 `accent.*.base`（深色自动换成更亮的系统深色变体）；前景小字、链接、索引条、搜索高亮、「+」图标用 `accent.*.text`；主按钮与选中胶囊用 `accent.*.fill` + `on-fill`（green / orange 底为黑字）。`ZTokens.Accent.color` / `ZAccent.color` 只为兼容保留，新代码不要再拿它当前景文字或按钮底。
- **浮起表面（s4，ZSurface.elevated / 按下态）上的说明文字用 t2**，不用 t3（浅色 t3 on s4 = 4.39:1）。
- 连接开关不加彩色外发光（浅色下会发脏）；§4 的「accent glow」只指状态切换瞬间的轻微光晕，深色下 alpha ≤ `glow.alpha`，浅色不加。

### 9.2 字号与分隔符
- **最小字号 11pt / 11sp**（正文、标签、索引条、导航控件）。例外只有 2–5 个字符的编码类内容：地区码徽章（SG / HK）、协议名（TUIC / VLESS），允许 10–10.5pt，且必须用 t2 或更深，不得叠加 t3 / t4 或强调色。节点索引条按 11pt，不再用 `n2xs − 0.5`。
- **「A · B · C」中点串联每屏最多一处**（原型本来就这么写，但现在用得太多）。其余改成分行、两列对齐，或真正的分组标题。地区码、协议名的全大写是内容，不是装饰，不要为了过 lint 改成小写。
- 中英文混排的分隔一律用「 · 」（前后各一个空格），不用中文逗号「，」作列表分隔。

### 9.3 场景漏斗：全 App 的签名物件
- 漏斗（全部 → 已测速 → 可连通 → 低于 200 ms，契约 §15.c `nodeFunnel`）是 Zephyr 独有的形状，作为**唯一签名物件**，在三个地方以同一种画法出现：场景 sheet（完整版）、首页场景卡（迷你版，替换「9 个可用」文字）、小组件 scenes-medium（可选，迷你版）。
- **迷你漏斗规格**：4 段水平细条，从左到右依次缩短，宽度按 `log10(count + 1)` 归一到卡片内容宽度（10⁷ 和 9 都要看得出差别）；条高 3pt、段间距 2pt、圆角 1.5pt；前三段 t3（深色 t4 也可，但整组必须配下方数字），最后一段（低于 200 ms 的可用数）用 `accent.*.base`。最后一段下方写数字 `{underThreshold}`，字号 caption、t1、等宽数字；不写其他三段的数字（完整数字在 sheet 里）。无障碍标签：「可连通 {reachable}，低于 200 毫秒 {underThreshold}」。
- **完整漏斗**（场景 sheet）：沿用原型 4 级，lede「检测自 {sourceCount} 个订阅中的 {poolSize} 个节点」；不显示「可访问 GPT」等按服务的级别（契约 §15.c）。
- 迷你漏斗的数据按场景取：契约 §19 `sceneFunnel(sceneId, …)`（该场景地区 + 4K 过滤范围内的漏斗），每张场景卡各不相同；完整漏斗（场景 sheet）仍用全局 `nodeFunnel`。
- 数据没取到时（`sceneFunnel` / `nodeFunnel` 抛错，或场景未选节点 `poolSize == 0`）：迷你漏斗不画，显示原文字「{n} 个可用」；不得画假比例。

### 9.4 节点页头部：先说人话再给数
- 大数字仍是总量（`total`），下方一行判断句：「可连通 {reachable} · 已检测 {tested}」（契约 §18.a，`reachableCount` 可选；为 null 时只写「已检测 {tested}」）。整行 t2，`reachable` 数字 t1；可连通为 0 时数字用 `red-text`。
- 这一行就是本页那一处中点（9.2）。搜索结果页不显示判断句。

### 9.5 指令结果（Raycast 式）
- 指令栏展开后的结果列表**按类型分组**，组顺序固定：① 解析出的指令（切模式 / 切场景 / 覆写，契约 §15.b `parseCommand`）② 场景 ③ 节点（地区 / 名称命中）④ 设置项 ⑤ 规则测试（输入是域名或 IP 时）。空组不显示组标题。
- 组标题：footnote、t3、句首大写（不用全大写小标签）。
- 每行：左侧图标（SF Symbol / Material Symbol，t2）、主文字 t1、副文字 t3（一行，超出截断）；**右侧对齐一个动作标签**说明回车会发生什么：「应用」「切换」「测速」「打开」「测试」。动作标签 footnote、`accent.*.text`、不加底色；第一行（默认动作）右侧额外显示回车键提示（iOS ⏎ 键帽 / Android 无，用加粗动作标签代替）。
- 键盘：回车执行第一行；方向键 / Tab 在行间移动（iPad / 外接键盘、Android 实体键盘）。结果最多 5 组 × 5 行，组末「显示全部 n 项」。
- 解析结果的预览仍「落在物上」：应用前在场景卡 / 计划卡上预览，不开对话框（原型 `render()` / `apply()`）。

### 9.6 延迟刻度条（Halide 式，200 ms 阈值）
- 位置：场景 sheet 候选列表顶部，列表标题下方一行。
- 横轴为延迟 0–600 ms（超过 600 ms 的贴在右端，超时不画，计入右侧文字），线性刻度；每个候选节点画一根短刻（宽 1pt、高 6pt，t3）；**200 ms 处一根长刻**（宽 1pt、高 12pt，t2，即 `latency.threshold-slow`），长刻上方写「200 ms」（caption、t3、等宽数字）。
- ≥ 200 ms 的短刻用 `screen.amber`（图形，可用原色），< 200 ms 用 t3；当前选中的出口节点短刻加高到 10pt、用 `accent.*.base`。
- 右端文字：「超时 {n}」（`red-text`，n = 0 时不显示）。整条高 20pt，左右与列表文字对齐。无障碍：「{m} 个候选，{k} 个低于 200 毫秒，超时 {n}」。
- 刻度条只用于场景 sheet（候选 ≤ 几十个）；节点页（千万级）不画。

### 9.7 悬浮指令栏与 Liquid Glass（iOS 26+）
- 首页指令栏与资料库按钮是**唯一**用玻璃的地方（悬浮工具条），其余卡片保持实色 `screen.s1/s2`。
- 指令栏**贴底**：iOS 贴安全区底部 + 8pt，下方不得露出可滚动内容（滚动内容在指令栏背后用 `screen.fade` 渐隐盖住）。Android / 鸿蒙同样贴底。
- **iOS 26 及以上**：指令栏与资料库按钮用系统 Liquid Glass（`glassEffect`，交互式，跟随强调色 tint 关闭，保持中性）；两者可放进同一个 `GlassEffectContainer`，相邻时融合。**iOS 17–25 回退**：`screen.glass`（`rgba(…,0.82)`）+ 系统模糊 `.ultraThinMaterial`，外观与现状一致。`if #available(iOS 26, *)` 分支，不提高最低系统版本。
- Android 保持现有模糊玻璃（`screen.glass` + RenderEffect 模糊，API 31+；以下纯 `screen.glass`）。**鸿蒙不适用 Liquid Glass**，登记为平台差异：用 `screen.glass` + `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` 或同等模糊。
- 玻璃上的文字用 t1 / t2，不用 t3（玻璃合成到最亮底时余量最小）。

### 9.8 跨平台一致性（评审漂移项的处理）
- 首页曲线：平滑大起伏（Catmull-Rom 或等效），填充 alpha 约 0.12，60% 高度处淡出；两端同原型。
- 首页字标「Zephyr」约 15pt semibold；最近连接 sheet 标题用术语「最近连接」。
- 规则页搜索框输入用正文字体；命中链里的值（域名、IP、层号）才用等宽。
- 节点行是否显示协议列：两端与原型统一为**不显示**（协议在节点详情里看）。
- 两端 mock 数据一律取 `contract/fixtures`，否则并排评审无法逐图对比；Android 补小组件快照。
- 字体：iOS SF / SF Mono、Android Inter / JetBrains Mono 是平台差异，可接受。

### 9.9 不该学（已决定不做，审阅时不再提出）
| 不做 | 理由 |
|---|---|
| 把首页整个做成线路图 / 道岔场景（「界面即世界」） | 节点、规则是 1e7–1e8 级要扫读的数据；IA 已在 §3 与契约 §17.e 定死，重做会让三端返工、重录全部基线。只借机制（漏斗、轨迹），不借整张皮 |
| 给连接状态配吉祥物 / 表情（「角色承载状态」） | VPN 是讲信任和安全的工具，严肃高风险场景慎用 |
| 硬件面板 / 玩味 3D / 友好金融这类高饱和风格 | 与 §1「保留桌面气质、强调色克制」冲突；token 只认桌面 + mobile.json |
| 为现有页面重出三个方向（三方向门） | 设计已由用户确认、三端在实现；只在新界面（今日卡、引导页、鸿蒙特有入口）用这道流程 |
| 换一套自定义展示字体 | 增加包体积，中文回退难处理，收益小于成本 |
| 照 lint 把地区码 / 协议名的全大写改掉 | 这是内容（ISO 码、协议名），不是装饰小标签 |
