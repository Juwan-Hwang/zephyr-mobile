# iOS ↔ Android 引擎与系统层一致性审计（只读）

- 仓库：`/workspace/repos/zephyr-mobile`，分支 `main` @ `6ffbaa2`（只读，未改动、未提交、未评论）
- 依据：`contract/zephyr-engine.md`（§0–§15.h）、`contract/mock-spec.md`、`contract/fixtures/*`、`design/notes/mobile-design-spec.md`、`design/notes/scale-architecture.md`
- 范围：iOS `apps/ios`（Core/、PacketTunnel/、Shared/Core、Shared/Intents、Widgets、App/、Packages/ZephyrKit）；Android `apps/android`（core-engine `com.zephyr.engine`、app/vpn、app/widget、app/tile、SubscriptionWorker）
- 方法：静态读代码。**未在真机/模拟器运行，未执行测试**。行号均为当前 main 的源文件行号。
- 分类：**(a) 漂移/缺陷**（应修，并指明哪端不符合契约/规范）；**(b) 合理平台差异**（保留，写明原因）；**(c) 契约缺口**（契约应补定义）
- 严重度：P0 发版阻断 / P1 / P2；Owner：A 契约/核心，B iOS，C Android

---

## 一、摘要表

| ID | 领域 | 差异（一句话） | 分类 | 不符合方 | 严重度 | Owner |
|---|---|---|---|---|---|---|
| E01 | 隧道生命周期 | Android 的「按需连接 / 受信任 Wi‑Fi / 受信任时断开」只有设置开关，没有任何执行方；iOS 映射成 NEOnDemandRule | a + c | Android | **P1** | C（A 补 Android 语义） |
| E02 | 隧道生命周期 | iOS 手动断开不关闭 on‑demand，开了「按需连接」后点断开会被系统立刻重连 | a | iOS | **P1** | B |
| E03 | 隧道生命周期 | 常开/Kill switch：Android 只靠系统 Always‑on（不检测、声明了 BOOT 权限却无接收器）；iOS 未设 includeAllNetworks/enforceRoutes | b + c | — | P2 | A/B/C |
| E04 | 网络切换 | Android `setMetered(false)` 且未 `setUnderlyingNetworks`：蜂窝网络下 VPN 被系统视为不计费；两端都没有定义网络切换后的连接清理/重探测 | a + c | Android | **P1** | C（A 补契约） |
| E05 | 崩溃恢复 | iOS 扩展崩溃后 SharedState 停在 connected，小组件/控制中心显示假“已连接”；Android 进程重启后模式丢失 | a | 双方 | P2 | B、C |
| E06 | 模式/全局出口 | Android 模式与 globalNodeId 存在 MockEngine 内存里：不落盘、`setGlobalNode` 不回填 → 通知/磁贴显示“任意节点”；iOS 持久化并补全 | a | Android | P2 | C |
| E07 | 错误态 | “没有订阅时连接”：iOS 报 `subscription_invalid`，Android 报 `subscription_not_found`；iOS 把所有 startVPNTunnel 失败都报成 `vpn_permission_denied` | a + c | 双方 | P2 | A、B |
| E08 | 连接状态 | Android Release 的 `ConnectionState.network` 是 Mock 写死的「家」Wi‑Fi；iOS 为 nil | a | Android | P2 | C |
| E09 | 配置默认值 | iOS 默认 TUN stack=`system`、DNS 主/备列表与契约 §13 不同（契约：gvisor，alidns→doh.pub，fallback 仅 1.1.1.1）；Android 与契约一致 | a | **iOS** | **P1**（stack；真机若 system 栈不可用则升 P0） | B |
| E10 | 路由 | iOS 在 NE 层排除局域网/链路本地/组播；Android 全部路由进 tun，无 LAN 绕过（全局模式下局域网会被代理） | c + a | Android | **P1** | A 定义，C 实现 |
| E11 | IPv6 | iOS 无论开关都声明 ::/0（关时由 mihomo 丢包）；Android 关时不声明 v6，系统默认阻断该地址族 | b | — | 信息 | A（契约注明） |
| E12 | 本地代理 | Android 始终开回环 mixed-port（随机私有端口，强制鉴权，忽略 `localProxyAuth=false`）；iOS 仅 `localProxyEnabled` 时开、尊重鉴权开关 | b + a + c | Android（鉴权开关） | P2 | C、A |
| E13 | find-process | Android `findProcess=true`，iOS `false` | b | — | — | — |
| E14 | 分应用代理 | Android 有 `excludedApps`（契约外扩展），但没有任何 UI 能设置；iOS 无（NE 分应用需 MDM） | b + a | Android（死字段） | P2 | C、A |
| E15 | 设置热应用 | iOS 改 DNS/TUN/本地代理时重写配置并热重载；Android `updateSettings` 不重载，重连前不生效 | a + c | Android | P2 | C |
| E16 | 设置校验 | iOS 校验 MTU 576–9000 并在隧道 clamp 1280–9000；Android 不校验直接 `setMtu` | a + c | Android | P2 | C、A |
| E17 | 生效订阅 | iOS 取 `subscriptions().first`；Android 另存 `active-subscription` 文件（与契约“列表第一个”可能分叉） | a | Android | P2 | C |
| E18 | strictRoute | `auto-route=false`，两端 `strictRoute` 都不起作用 | c | — | P2 | A |
| E19 | Go 内存上限 | iOS 30 MB，Android 48 MB | b | — | — | — |
| E20 | 测速并发 | 扩展内 `zm_url_test` 并发：iOS 8，Android 32 | b + c | — | P2 | A |
| E21 | 自动切换时机 | iOS 只在前台且已连接时探测；Android 前台服务里 60 s 一轮常驻 | b + c | — | P2 | A |
| E22 | 自动切换判定 | Android 缺“全组不通不计失败”“探测期间换节点丢弃”两道守卫；select 失败不回滚却报“已切换” | a | Android | **P1** | C |
| E23 | 自动切换 | 「仅 Wi‑Fi 测速」：iOS 探测时遵守，Android 忽略 | a + c | Android | P2 | C、A |
| E24 | AI 场景提示 | iOS 同一次故障只提示一次；Android 每 60 s 发一次事件，首页每轮弹 toast | a | Android | P2 | C |
| E25 | 服务/出口探测 | iOS 仅在 retestScene 时探测；Android 后台约 10 分钟一轮 `probeServices` | c | — | P2 | A |
| E26 | 场景重测 | Android `scanTargets(maxAge=1ms)` 每次全量重测；契约 §15.e 要求传 TTL（iOS 正确） | a | Android | P2 | C |
| E27 | needsReload | 重载失败：Android 抛 `core_crashed` 给 UI，iOS 静默吞掉；“连接中”时 iOS 排队补重载，Android 不处理 | c | — | P2 | A |
| E28 | 陈旧场景自动重测 | iOS 有（SceneRetestPlanner）；Android 无 | a / c | Android | P2 | C、A |
| E29 | 订阅到期判定 | iOS 自写 AutoUpdatePlanner：`autoUpdateHours ≤ 0` 回落到设置/12 h → **“手动更新（0）”的订阅也会被自动更新**；Android 用核心 `dueSubscriptions`（0 = 不更新） | a | **iOS** | **P1** | B |
| E30 | 订阅更新调度 | Android WorkManager 只要求 `CONNECTED`，**忽略「仅 Wi‑Fi 更新」**；iOS 用 NWPath 判断非计费 | a | Android | **P1** | C |
| E31 | 本地订阅 | 核心 `due()` 不排除无 url 的本地订阅 → Android 每小时静默失败一次；iOS 只看有 url 的订阅 | a | 核心 | P2 | A |
| E32 | 导入默认间隔 | iOS 导入时写死 12 h；Android 取设置 `autoUpdateHours` | a | iOS | P2 | B |
| E33 | 订阅更新后重载 | iOS 每次更新都重写配置并重载；Android 只在生效订阅更新时重载 | b / c | — | P2 | A |
| E34 | 导入载荷 §15 | Android 没接 `parseImportPayload`：桌面同步码 `zephyr://import?...`、`d=` 多条、`clash://` 扫码/粘贴都会被拒；iOS 已接 | a | **Android** | **P1** | C |
| E35 | 订阅拉取 | 超时/大小上限/重定向/UA 各不相同；两端都没有契约 §14 要求的平台层 SSRF/DNS 校验，且都先联网再交给核心校验 | a + c | 双方 | P2 | A、B、C |
| E36 | 测速有效期 | Android `testedCount`、今日“最快”写死 24 h，不跟 `latencyTtlHours`；iOS 全部跟随 | a | Android | P2 | C |
| E37 | 节点行延迟 | Android `nodeRows` 不调 `cachedLatencies`，重启后节点列表全显示“未测”；iOS 回填 | a | **Android** | **P1** | C |
| E38 | TCP 握手测速 | 两端一致：并发 32、超时 3 s、进程级名额 | ✓ | — | — | — |
| E39 | 今日用量账本 | 计数器回退：iOS 计入新读数并在启动时复位；Android 计 0 且不复位（会少算）；落盘 iOS 5 s，Android 30 s | a | Android | P2 | C |
| E40 | 命令解析样本 | `command-parse-v1.json` 两端单测都没接（契约 §15.b 要求逐条比对）；iOS 还多出样本里没有的 `scope` token | a | 双方 | P2 | B、C |
| E41 | 命令建议 | iOS 在引擎内实现（§14.w）；Android Release 下 `commandSuggestions` 返回 []，改由 UI 的 CommandPlanner 实现 | b / c | — | P2 | A、C |
| E42 | 持久化/迁移 | 设置：iOS JSON 必填字段严格解码（新增字段缺失时整份回落默认）；Android DataStore 宽松解码。凭据：iOS 存钥匙串，Android 明文文件。首次默认值两端不同 | a + c | 双方 | P2 | A、B、C |
| E43 | 错误映射 | Android `SceneNotFound→internal`；iOS `SubscriptionNotFound→subscription_invalid`、`StaleToken→internal`；两端 `Invalid→rule_input_invalid`、`Io/Corrupt→internal` | a + c | 双方 | P2 | A、B、C |
| E44 | 小组件/实时活动/QS | 刷新节奏与动作各按平台惯例；Android 小组件不会在零点归零，iOS 有零点条目 | b + a | Android（零点） | P2 | C |
| E45 | 连接列表上限 | iOS `activeConnections(limit: 500)`，契约 ≤200；Android 200 | a | iOS | P2 | B |
| E46 | 日志级别 | 两端 mihomo `log-level` 都写死 `warning`，日志页选 debug/info 也拿不到 | c | — | P2 | A |
| E47 | 共享样本测试 | mock‑v0、uhd‑names 两端都跑；import‑payload 只有 iOS 跑；command‑parse 两端都没跑 | a | Android、双方 | P2 | B、C |

**严重度统计**：P0 0 个（E09 有升级为 P0 的可能，待真机验证）；P1 10 个（E01、E02、E04、E09、E10、E22、E29、E30、E34、E37）；其余为 P2/信息。

---

## 二、优先处理（Top 10）

1. **E34 Android 未实现 §15 导入载荷**（P1，C）：桌面“同步到手机”二维码在 Android 上整条流程用不了。
2. **E29 iOS 自动更新会更新“手动”订阅**（P1，B）：和核心 `due()` 的语义冲突，应改用核心 `dueSubscriptions`，或把 `≤0` 视为不更新。
3. **E30 / E01 Android 设置开关无效**（P1，C）：「仅 Wi‑Fi 更新」不生效会消耗蜂窝流量；「按需连接 / 受信任 Wi‑Fi / 仅 Wi‑Fi 测速」也都是空开关。
4. **E09 iOS 默认 TUN 栈与 DNS 偏离契约 §13**（P1，B）：契约写明「iOS NE 默认 gvisor」，iOS 实际下发 `system`。
5. **E37 Android 节点列表不显示缓存延迟**（P1，C）：违背 §5「latencyMs 只给缓存值」和 scale-architecture「只显示缓存值」。
6. **E22 Android 自动切换缺少守卫**（P1，C）：断网、或探测地址本身被墙时，会把视频/其他场景的健康节点误判为失败并切走。
7. **E10 Android 没有局域网绕过**（P1，A+C）：全局模式下打印机、投屏、路由器后台会走代理；契约应把 LAN 绕过写成两端共同行为。
8. **E04 Android `setMetered(false)`**（P1，C）：在蜂窝网络下，其他 App 会把 VPN 当成不计费网络大量下载。
9. **E02 iOS 按需连接下无法手动断开**（P1，B）：stop 前应先 `isOnDemandEnabled=false`，或改用系统建议的做法。
10. **E40/E47 共享样本未进单测**（P2，B/C）：command‑parse 样本两端都没接，import‑payload 样本 Android 没接，这正是 E34 漏掉的原因。

---

## 三、逐项详情

### A. VPN / 隧道生命周期

**E01 按需连接 / 受信任 Wi‑Fi（a+c，P1，C；A 补语义）**
- iOS：`Shared/Core/OnDemandPlan.swift:16-26` 把设置转成规则，`Shared/Intents/TunnelController.swift:87-110` 写成 `NEOnDemandRuleDisconnect(ssidMatch)` / `NEOnDemandRuleConnect`；在 `Core/CoreEngine.swift:1050-1054`（设置变更）和 `Core/CoreEngine+Live.swift:50-52`（连接时 `create: true`）下发。
- Android：`Model.kt:354-356` 有字段，`ui/settings/SettingsScreen.kt:72-74` 有开关，但全仓库没有 `ConnectivityManager` / `NetworkCallback` / SSID 判断（grep `onDemand|trustedWifi|NetworkCallback` 只命中 UI 和模型）。
- 判定：Android 漂移（UI 承诺了功能但不执行）。契约 §8 只列了字段，没写平台语义 → 同时属于契约缺口。建议 A 在契约里写明：Android `onDemand` = 网络可用时自动连（NetworkCallback + 前台服务），或明确隐藏开关、引导用户用系统 Always‑on；受信任 Wi‑Fi 在 Android 10+ 读 SSID 需要定位权限，也要写进契约。

**E02 iOS 手动断开与 on‑demand 冲突（a，P1，B）**
- `Shared/Intents/TunnelController.swift:62` 断开只调 `stopVPNTunnel()`，不改 `isOnDemandEnabled`。开了「按需连接」（规则末尾是 `NEOnDemandRuleConnect`，:98）时，系统会马上重新拉起隧道。
- 建议：用户主动断开时先把 `isOnDemandEnabled` 置 false 并保存，下次主动连接时再恢复。Android 没有对应问题（见 E01）。

**E03 Always‑on / Kill switch（b+c，P2）**
- Android：`AndroidManifest.xml:10` 声明了 `RECEIVE_BOOT_COMPLETED`，但没有任何 BOOT 接收器；VpnService 能被系统 Always‑on 拉起（`ZephyrVpnService.kt:41-46` 的 `else -> start()` 会处理 `android.net.VpnService` 动作），但没有检测 `isAlwaysOn` / `isLockdownEnabled`，也没有提示。
- iOS：`TunnelController.swift:120-126` 只设了 `disconnectOnSleep=false`，没设 `includeAllNetworks` / `enforceRoutes`。
- 判定：两端 Kill switch 的能力本来就不同（Android 由系统设置提供，iOS 需要 `includeAllNetworks`，会影响本地网络），属于平台差异；契约应写明两端各自的承诺。删除 Android 未使用的 BOOT 权限，或补上接收器（C）。

**E04 网络切换 / 计费（a+c，P1，C；A 补契约）**
- Android：`TunBridge.kt:89` `setMetered(false)`；全仓库没有 `setUnderlyingNetworks` / `NetworkCallback`。结果：蜂窝网络下系统把 VPN 当成不计费网络，其他 App（以及将来要用 `UNMETERED` 约束的 WorkManager）都会误判。网络切换后也不会主动关闭旧连接或重新探测。
- iOS：NE 自己处理路径变化（`reasserting` 映射为 connecting，`App/SystemTunnelPort.swift:102-103`），计费属性由系统沿用底层网络；同样没有在网络切换时 `closeAll`/重探测。
- 建议：C 去掉 `setMetered(false)`，或用 NetworkCallback 维护 `setUnderlyingNetworks`。A 在契约 §1/§11 写明网络切换后两端的统一动作（例如可选 closeAll，下一轮立即探测场景）。

**E05 崩溃恢复（a，P2，B/C）**
- iOS：扩展只在 `startTunnel`/`stopTunnel`/失败时写 `SharedState.connection`（`PacketTunnel/ZephyrPacketTunnelProvider.swift:303-309`）。扩展被 jetsam 杀掉时不会写 disconnected；小组件和控制中心读的是 SharedState（`Widgets/ZephyrConnectionControl.swift` 的 `currentValue`，`Widgets/SharedTimelineProvider.swift:29-31`），App 不在前台时会一直显示“已连接”。App 自己读 NEVPNStatus，不受影响。建议小组件 timeline/控制中心改为读 `NETunnelProviderManager` 的状态，或在 SharedState 写心跳，读的一方判断是否过期。
- Android：`START_STICKY`（`ZephyrVpnService.kt:46`）进程被杀后会重启并重连；用量账本最多丢 30 s（E39）；模式丢失（E06）。
- 两端都没有在启动时调用核心的 `rebuildFromSubscriptions`（§15.f“启动修复用”）——属于可选项，记录在此。

**E06 模式与全局出口（a，P2，C）**
- Android：`CoreEngine.kt:637-640` 的 `setMode` 只改 MockEngine 内存里的状态（`MockEngine.kt:84-89`），不落盘，进程重启后回到 RULE；`CoreEngine.kt:558-567` 的 `setGlobalNode` 不回填 `ConnectionState.globalNodeId`，所以 `Notifications.kt` 和 `ZephyrTileService.kt` 在全局模式下显示“任意节点”。
- iOS：模式持久化在 SharedState `tunnel.mode`（`TunnelController.swift:67-68`），扩展启动时注入（`ZephyrPacketTunnelProvider.swift:100`）；`CoreEngine.swift:194-223` 用 `core.globalNode()` 补全 globalNodeId。
- 建议：C 把模式持久化，并在 connectionState 中用 `globalNode()` 补全。

**E07 连接失败的错误码（a+c，P2，A/B）**
- 没有订阅时：iOS `CoreEngine.swift:948-950` 抛 `subscriptionInvalid`，扩展找不到配置时报 `subscription_invalid`（`ZephyrPacketTunnelProvider.swift:43`，与 §14.x 一致）；Android `TunBridge.kt:69-77` 报 `SUBSCRIPTION_NOT_FOUND`。
- iOS `App/SystemTunnelPort.swift:45-48`：所有 `setConnected(true)` 错误（含 `configMissing`、`startVPNTunnel` 的非权限错误）都被映射成 `vpnPermissionDenied`，UI 会误导用户。
- 建议：A 在 §10 明确“尚无订阅时连接”的错误码（建议沿用 §14.x 的 `subscription_invalid`，或新增专用码）；B 只把用户拒绝授权映射为 `vpn_permission_denied`。

**E08 Android 假的网络信息（a，P2，C）**
- `MockEngine.kt:50-51` 写死 `NetworkInfo(WIFI, "家")`，`CoreEngine.connectionState()`（:788-791）在 Release 原样透传；iOS `SystemTunnelPort.state` 不设 network（nil）。目前两端 UI 都不读 `network`，所以是 P2；但这违背 Android 自己“Release 不展示合成数据”（review P0‑1）的原则。

### B. mihomo 配置生成与注入

注入路径（b，保留）：iOS 由 App 生成 YAML 并写入 App Group `core/config.yaml`，fd 用哨兵 -1，扩展替换后 `zm_start`（`CoreEngine.swift:946-958`、`ZephyrPacketTunnelProvider.swift:94-102`，符合 §14.x）；Android 在同一进程拿到真实 fd 直接生成并 `zm_start`（`TunBridge.kt:40-55`）。原因是 iOS NE 有约 50 MB 内存上限，扩展不能链接 Rust 核心。

**E09 iOS 默认 TUN/DNS 偏离 §13（a，P1，B）**
- 契约 §13 要求默认值：`DnsSettings(fakeIp: true, nameservers: [alidns, doh.pub], fallback: [1.1.1.1], ipv6: false)`、`TunSettings(stack: gvisor, mtu: 9000, ...)`，并写明“iOS NE 默认 gvisor”。
- iOS：`Packages/ZephyrKit/Sources/ZephyrKit/Models.swift:551-552`（nameservers 顺序是 `[doh.pub, alidns]`，fallback 多了 `dns.google`）、`:568`（`stack: .system`）；Release 首次启动的设置 `Core/CoreEngine.swift:1082` 直接用这两个默认值，经 `runtimeOptions`（:960-969）下发给 mihomo。
- Android：`Model.kt:333,344` 与契约一致。
- 风险：mihomo 的 `system` 栈要在 NE 进程里监听 tun 地址，可行性未验证；若真机不可用，Release 首次连接会全部失败，应升为 P0。建议 B 立即改为 gvisor 和契约的 DNS 列表，并为已落盘的旧 `settings.json` 做迁移判断（不要覆盖用户主动改过的值）。

**E10 局域网绕过（c+a，P1，A 定义 / C 实现）**
- iOS：`PacketTunnel/TunnelNetworkSettingsFactory.swift:14-16, 26-28` 排除 10/8、127/8、169.254/16、172.16/12、192.168/16、224/4 以及 fe80::/10、fc00::/7、ff00::/8（`TunnelConfiguration.swift:24-36`），`bypassLAN` 默认 true（`Shared/Core/SharedState.swift:154`），用户不能改。
- Android：`TunBridge.kt:84-87` 只有 `addRoute("0.0.0.0",0)`，没有排除任何网段。规则模式下，若订阅规则没有 private CIDR → DIRECT，局域网流量会进代理；全局模式下一定进代理。
- 契约没有提到 LAN 绕过。建议 A 写成两端共同行为（或在 `runtimeConfig` 前插 `IP-CIDR,私网,DIRECT`，与 iOS 路由层排除形成双保险）；C 在 API 33+ 用 `excludeRoute`，低版本用补集路由。

**E11 IPv6（b，信息）**
- iOS 总是把 ::/0 路由进隧道（`TunnelNetworkSettingsFactory.swift:21-25`，注释写明是为了防泄露），IPv6 关闭时由 mihomo 丢弃；Android 在 IPv6 关闭时不加 v6 地址和路由（`TunBridge.kt:87`），按 `VpnService.Builder.allowFamily` 的文档，此时系统默认阻断该地址族。两端结果相同（都不泄露），实现不同，保留；建议 A 在契约 §13 补一句“IPv6 关闭 = 阻断，不得旁路”。

**E12 本地代理 / 回环端口（b+a+c，P2，C/A）**
- Android：`CoreEngine.kt:256-288` 总是传 `LocalProxy(port, credential)`。未开启时使用 20000–60000 内的随机私有端口（`privateProbePort`），并且**总是带凭据**，忽略 `localProxyAuth=false`。原因（b）：App 自身被排除在 VPN 之外（`TunBridge.kt:90`），服务/出口探测只能走回环代理（`ProxyProbe.kt`）。
- iOS：`CoreEngine.swift:973-976` 只在 `localProxyEnabled` 且端口 ≥1024 时开启，并尊重鉴权开关。
- 契约 §14.z ④ 写的是“默认 null”。建议：A 追加 Android 例外（始终开私有鉴权端口，仅供探测）；C 在用户主动开启本地代理时尊重 `localProxyAuth`。

**E13 find-process（b）**：Android `findProcess=true`（`CoreEngine.kt:256`），iOS `false`（`CoreEngine.swift:968`）。iOS 拿不到发起连接的进程，契约 §13 已注明 iOS 的 `ConnectionInfo.app` 恒为 null。保留。

**E14 分应用代理（b+a，P2，C/A）**
- Android：`Model.kt:349` 的 `excludedApps`（注释：契约外的 Android 扩展），在 `TunBridge.kt:91` 生效；但 `ui/` 目录里没有任何地方写这个字段，用户无法设置，等于死字段。iOS 不可能实现（NE 分应用 VPN 需要 MDM）。
- 建议：C 补上 UI 或删除该字段；A 在契约里登记为“Android 专有扩展”。

**E15 设置变更热应用（a+c，P2，C）**
- iOS：`CoreEngine.swift:1048-1049, 1057-1060` 在 dns/tun/本地代理任一字段变化时重写配置并 `reloadConfig`。注意：mtu/ipv6 属于 NE 网络设置，需要重连才会真正生效，iOS 目前也没有提示。
- Android：`CoreEngine.kt:435-439` 只下发 TTL，不调 `reloader`；DNS/本地代理改了要重连才生效，tun 层参数同样需要重建。
- 建议：C 对 dns/本地代理调用 `reloadIfRunning()`；A 在契约中区分“热重载生效”和“需要重连生效”的字段，两端 UI 统一提示。

**E16 设置校验（a+c，P2，C/A）**：iOS `CoreEngine.swift:1029-1031` 校验端口、TTL>0、自动更新>0、MTU 576…9000，隧道里再 clamp 到 1280…9000（`TunnelConfiguration.swift:38-39`）；核心把 mtu clamp 到 1280…65535（`core-mobile/src/runtime_config.rs:131`）；Android 不校验，`TunBridge.kt:83` 直接 `setMtu`。建议 A 在契约里给出取值范围，C 补校验。

**E17 生效订阅（a，P2，C）**：契约 §14.w“生效订阅 = 列表第一个，与运行配置同源”。iOS `CoreEngine.swift:948` 取 `subscriptions().first`；Android 另存 `active-subscription` 文件（`CoreEngine.kt:235-240`），只在导入（无生效订阅时）和删除时更新。当前顺序一致，但这是一份多余的状态：核心编译第 2 层“订阅规则”时用的是列表第一个，一旦列表顺序变化，就会出现“规则页看到的”和“实际运行的”不是同一个订阅。

**E18 strictRoute（c，P2，A）**：核心固定 `auto-route: false`（`runtime_config.rs:135`），mihomo 的 `strict-route` 只在 auto-route 下生效，所以两端设置页的这个开关都不起作用。契约 §13 应注明“移动端无效”，或在 UI 隐藏。

**E19 Go 内存上限（b）**：iOS 30 MB（`ZephyrPacketTunnelProvider.swift:49`，NE 约 50 MB 上限），Android 48 MB（`TunBridge.kt:60`）。保留。

**E20 扩展内测速并发（b+c，P2，A）**：iOS 8（`ZephyrPacketTunnelProvider.swift:173`），Android 32（`CoreEngine.kt:602`），超时都是 5000 ms，URL 都是 gstatic generate_204。iOS 受 NE 内存限制，并发低是合理的；契约 §14.w 应给出并发值或上限。

### C. 场景应用、自动切换、needsReload

`applySceneChange` 的 needsReload 分支两端一致：false → `selectInGroup`，true → 重写配置 + reload（iOS `CoreEngine.swift:393-406`，Android `CoreEngine.kt:384-394`）。`setGlobalNode` 两端都是“需要时先重载，再总是 select GLOBAL”（§14.w）✓。AI 场景都不上报计数、不自动切换（§14.y）✓。探测间隔都是 60 s、URL 都是 gstatic、超时 5 s ✓。阈值/冷却两端都用核心默认（3 次 / 30 s），都没调 `setFailoverPolicy` ✓。

**E21 探测在哪里跑（b+c，P2，A）**
- iOS：`Core/CoreEngine+Failover.swift:30-47` 加上 `ZephyrFeatures/App/AppModel+Streams.swift:105-121`，只在“前台且已连接”时运行；App 进入后台就停止（扩展不链接核心，App 会被挂起）。
- Android：`ZephyrVpnService.kt:112-116`，前台服务里 60 s 一轮常驻。
- 结果：iOS 在后台出口断掉时不会自动切换。这是平台限制，保留；契约 v0.2「场景自动切换」应写明 iOS 只在前台生效。

**E22 Android 自动切换缺守卫（a，P1，C）**
- iOS `CoreEngine+Failover.swift:80-84`：全组成员都不通时视为探测本身不可用，不上报；探测期间用户换了节点就丢弃结果。`:99-106`：`selectInGroup` 失败时用 `applySceneChange(previous)` 撤回核心里的选择，不报“已切换”。
- Android `CoreEngine.kt:493-506`：选中节点失败就上报 `reportSceneProbe(false)`，没有“全组不通”判断，也没有“换节点”检查；`l.select` 的结果被 `runCatching` 吞掉，之后照样发 `SceneFailoverEvent` 并 `scenesBump`。
- 影响：断网、或 generate_204 被墙约 3 分钟，视频/其他场景就会被自动切走；切换失败时 UI 显示的节点和实际不一致。

**E23 「仅 Wi‑Fi 测速」与探测（a+c，P2）**：iOS `CoreEngine+Failover.swift:39` 在计费网络下跳过；Android 不判断。契约没说 `testOnWifiOnly` 是否覆盖故障探测，建议 A 写明（倾向于覆盖：探测本身就是测速），C 跟进。

**E24 AI 出口无响应的提示频率（a，P2，C）**：iOS 用 `FailoverState`（`CoreEngine+Failover.swift:18-24, 86-89`）保证同一次故障只提示一次；Android `CoreEngine.kt:497-501` 每轮都发事件，`ui/home/HomeViewModel.kt:99-102` 每次都弹 toast。

**E25 服务健康/出口探测频率（c，P2，A）**：契约 §14.z 只定义了 retestScene 时探测。iOS 只在 retestScene 时做（`CoreEngine.swift:410-446`）；Android 除 retestScene 外，还在 `probeScenes` 里每 10 轮做一次 `probeServices`（`CoreEngine.kt:509`，约 10 分钟，后台也跑）。结果是 `Scene.services` 和 `exitIp` 的新鲜度两端不同。建议契约写明是否允许周期探测、周期多长。

**E26 场景重测扫描（a，P2，C）**：契约 §15.e 规定 `scanTargets(scene.scanQuery, 512, now, ttl)`。iOS `CoreEngine.swift:634-636` 传 TTL ✓；Android `CoreEngine.kt:457-458` 传 `maxAge=1L`（代码注释：“1 ms = 全部、最旧优先”），每次重测都把最多 512 个节点全测一遍，有效期内已测的也不跳过。

**E27 重载失败的语义（c，P2，A）**：iOS `CoreEngine+Live.swift:64-76` 写配置失败直接 return，`reloadConfig` 用 `try?`，“连接中”时排队等连上后补重载（`afterConnect`，:79-90）；Android `CoreEngine.kt:359-362` 失败抛 `CORE_CRASHED`，导致 applySceneChange/overrideHost 在 UI 上报错，未运行时不处理（下次启动会读到新配置）。两种都说得通，但用户看到的不一致。契约 §14 应规定：重载失败时操作是否回滚、报什么错码。

**E28 陈旧场景自动重测（a/c，P2）**：iOS `App/SubscriptionAutoUpdater.swift:100-116` 加 `SceneRetestPlanner`，在前台/BG 刷新时、已连接且结果超过 TTL 的场景会自动重测（30 分钟退避，遵守仅 Wi‑Fi）；Android 没有。设计规范没有明确要求，建议 A 决定是否纳入契约。

### D. 订阅自动更新

| 项 | iOS | Android |
|---|---|---|
| 调度 | BGAppRefresh `earliestBeginDate` 4 h + 回前台/启动检查（`SubscriptionAutoUpdater.swift:43-62`） | WorkManager 每小时周期任务（`SubscriptionWorker.kt:30-33`） |
| 到期判定 | 平台自写 `AutoUpdatePlanner.due`（`AutoUpdatePlanner.swift:16-26`） | 核心 `dueSubscriptions`（`CoreEngine.kt:217-224`） |
| 约束 | `updateOnWifiOnly` → NWPath 非计费、非受限（:85） | 只有 `NetworkType.CONNECTED` + 电量不低（:31） |
| 重试 | 同一订阅 15 分钟退避（`AutoUpdatePlanner.swift:10`） | 抛异常时 `Result.retry()`（WorkManager 指数退避）；单个订阅失败等下一轮 |
| 差异提示 | 更新结果只写日志 | 同左 |
| 附带 | 陈旧场景重测、规则集刷新 | 规则集/GEO 刷新（:221），生效订阅更新时重载（:222） |

调度节奏的差别属于平台惯例（b）。具体问题：

**E29 iOS 会自动更新“手动”订阅（a，P1，B）**：核心 `core-mobile/src/subs.rs:287-293` 只返回 `auto_update_hours > 0` 的订阅（0 = 不自动更新；§15 的导入码允许 `auto ∈ [0,720]`）。iOS `AutoUpdatePlanner.swift:21-22` 在 `autoUpdateHours ≤ 0` 时回落到设置值或 12 h。用户用导入码设为 0 的订阅会每 12 h 被拉取一次。建议直接用核心 `dueSubscriptions`（和 Android 同源），或把 ≤0 视为跳过。

**E30 Android 忽略「仅 Wi‑Fi 更新」（a，P1，C）**：`SubscriptionWorker.kt:31` 只要求 `NetworkType.CONNECTED`，而设置页 `ui/subs/SubscriptionsScreen.kt:159` 有这个开关。按设置使用 `NetworkType.UNMETERED` 即可（还需先修 E04 的 `setMetered(false)`，否则 VPN 连着时系统永远判定为不计费）。

**E31 本地订阅进入到期列表（a，P2，A）**：核心 `due()` 不看 url，本地导入的订阅超过间隔后会一直处于到期状态；Android 每小时 `updateSubscription` 一次，因为“本地配置”抛 `SUBSCRIPTION_INVALID`，被静默过滤（`CoreEngine.kt:190, 220`）。iOS 只看有 url 的订阅，不受影响。建议 A 让 `due()` 排除 `url == None`。

**E32 导入时的默认间隔（a，P2，B）**：§15 规定 `item.autoUpdateHours ?? 默认`。iOS `CoreEngine.swift:747` 写死 `?? 12`；Android `CoreEngine.kt:176` 取设置 `autoUpdateHours`。iOS 应改为读设置。

**E33 更新后重载（b/c，P2）**：iOS 每次 `updateSubscription` 都 `reloadTunnelIfRunning`（`CoreEngine.swift:841`，`updateAll` 只重载一次，:858）；Android 只在生效订阅更新时重载（`CoreEngine.kt:222`；手动 `updateSubscription` 不重载）。Android 的手动更新路径：用户更新生效订阅后，运行中的 mihomo 仍用旧节点，直到重连。建议 A 写明“生效订阅变更后必须重载”，C 在手动更新路径补上。

**E34 Android 未接 §15 导入载荷（a，P1，C）**：契约 §15 规定“平台流程：`parseImportPayload` → 多条时列出确认 → 每条拉取导入”。iOS `CoreEngine.swift:719-742` 已接（加上 Swift 侧 `ZephyrKit/ImportPayload.swift` 预解析）；Android 搜不到 `parseImportPayload`。`CoreEngine.kt:169-170` 对 QR/URL 只接受 `http(s)://`；`MainActivity.kt` 的深链只取 `url` 查询参数，不支持 `d=` 多条、`auto=`、`name=`。

**E35 订阅拉取（a+c，P2，A/B/C）**：iOS `URLSession`，超时 30 s，没有大小上限，自动跟随重定向（`CoreEngine.swift:898-911`）；Android `HttpURLConnection` 连接 15 s/读取 30 s，32 MB 上限，手动跟随最多 5 次重定向（`SubscriptionFetcher.kt:11, 26`）；UA 也不同。契约 §14 要求“SSRF/DNS 校验在平台层”，两端都没有实现（grep 不到相关判断），而且都是先联网拉取、导入时才交给核心做 URL 校验。建议 A 在契约中给出统一的拉取规范（超时、大小、重定向、私网地址策略），B/C 实现。

### E. 测速（并发、超时、TTL、fastestNodes）

| 项 | iOS | Android | 契约 |
|---|---|---|---|
| 未连接 TCP 握手 | 32 并发 / 3 s / 进程级 AsyncLimiter（`CoreEngine+TcpPing.swift:10-14`） | 32 / 3 s / 进程级 Semaphore（`TcpPinger.kt:19-20`） | §14.u ✓ 一致 |
| 已连接 url test | 扩展内并发 8，超时 5000 | 进程内并发 32，超时 5000 | 未规定（E20） |
| 批大小 | 512 / 扫描每组 64 | 512 / 扫描每组 64 | ✓ |
| setLatencyTtlHours | 启动时 + 变更时（`CoreEngine.swift:94, 1045-1047`） | 只在 `updateSettings` 时（启动时由 SettingsStore 回放已保存设置） | ✓ 等效（默认都是 24） |
| testedCount / fastest / cachedLatencies 的 maxAge | 全部用 TTL（`CoreEngine.swift:280, 530, 584, 591`） | testedCount 与今日最快写死 `DAY_MS`（`CoreEngine.kt:696, 819`） | §15.e 要求跟随设置（E36） |

**E36（a，P2，C）**：见上表。

**E37 Android 节点行不回填缓存延迟（a，P1，C）**：`CoreEngine.kt:712-727` 的 `nodeRows` 直接 `p.rows.map(::row)`，`row()`（:758-761）不带延迟，全文件没有 `cachedLatencies` 调用；核心 `NodeRow` 本身也没有延迟字段。iOS `CoreEngine.swift:582-588` 按 TTL 回填。结果：Android 重启 App 或滚回已测过的区段时都显示“未测”，只有当次会话里 `latencyUpdates` 推送过的行有值；也会让“400 ms 停止滚动后测可见行”反复重测已测节点。

### F. hostOverride / 规则层 0

两端都调用核心 `overrideHost` 后重载（iOS `CoreEngine.swift:472-478`，Android `CoreEngine.kt:682-687`），第 1 层由核心维护（§14 规则层 0）✓。差别只在错误映射：iOS 把 NotFound 映射为 `rule_input_invalid`，Android 映射为 `scene_not_found`（归入 E43）。

### G. 用量与流量统计

| 项 | iOS | Android |
|---|---|---|
| 谁写 | PacketTunnel 扩展（`ZephyrPacketTunnelProvider.swift:208-210, 260-265`） | 同一进程的 `traffic()` 采样（`CoreEngine.kt:645`），由 VPN 服务的 watcher 驱动 |
| 存哪 | App Group `core/usage.json`（扩展写、App 只读；`UsageLedger.swift:58`） | `filesDir/core/usage.json`（`CoreEngine.kt:807`） |
| 落盘 | 每 5 s | 每 30 s + 停止时 flush（`UsageLedger.kt:37`、`ZephyrVpnService.kt` stop） |
| 在线时长 | 采样间隔最多计 10 s | 间隔 1–10 s 才计 |
| 计数器回退 | 计入新读数；`tunnelStarted()` 显式复位（`UsageLedger.swift:26-29, 39`） | 计 0；启动时不复位（`UsageLedger.kt:29`） |
| regionsToday / fastest | 场景出口地区 + 全局节点地区；最快用 TTL | 同上；最快写死 24 h |

存储位置的差异是平台使然（b，iOS 需要跨进程）。**E39（a，P2，C）**：Android 回退时计 0，且没有“启动复位”。新进程第一次读到的累计值如果大于上次保存的 `lastTotal`，会被算成 `total - lastTotal`（少算）；mihomo 重启后的第一段流量也会丢。建议与 iOS 一致：在 attach/start 时复位 `lastTotal`，回退时计入新读数。

### H. 命令解析与共享样本

**E40（a，P2，B/C）**：契约 §15.b 规定两端单测要逐条比对 `command-parse-v1.json`。iOS `ZephyrFeaturesTests/CommandTokenizerTests.swift` 和 Android `app/src/test/.../CommandParserTest.kt` 都是手写用例，没有读取样本文件。另外，iOS 的 token 有 `.scope` 类型（`CommandTokenizerTests.swift:27`：`[.service, .region, .scope]`），而样本里的 `tokens[].kind` 只有 service、region、action 三种；接入样本时 iOS 要把 scope 从 tokens 里分开比对。

**E41（b/c，P2）**：iOS `Core/CoreEngine+Commands.swift` 在引擎内用真实核心实现 §9（符合 §14.w）；Android `CoreEngine.kt:834-835` 在 Release 下返回 []，由 UI 的 CommandPlanner 实现。只要结果一致，放在哪一层都可以；但契约 §9 的“引擎接口”在 Android 上实际是空的，建议 A 明确 §9 是否仍然是引擎接口。

**E47 共享样本测试矩阵**

| 样本 | iOS | Android | CI 是否执行 |
|---|---|---|---|
| mock-v0.json | ✓ `ZephyrMockTests/FixtureTests.swift` | ✓ `core-engine/.../MockFixturesTest.kt` | iOS：scheme Zephyr 包含 ZephyrMockTests（`project.yml:467-468`）；Android：`testDebugUnitTest`（`mobile.yml:218`） |
| uhd-names-v1.json | ✓ `UHDFixtureTests.swift` | ✓ `UhdNamesFixtureTest.kt` | 同上 |
| import-payload-v1.json | ✓ `ZephyrKitTests/ImportPayloadTests.swift` | ✗ | — |
| command-parse-v1.json | ✗ | ✗ | 只有生成器漂移检查（`mobile.yml:61`） |

### I. 持久化位置与迁移

| 数据 | iOS | Android |
|---|---|---|
| 核心数据（节点/规则/订阅） | `Application Support/zephyr-core`（`CoreEngine.swift:113-117`） | `filesDir/core`（`AppGraph.kt`） |
| 引擎设置 | `zephyr-core/settings.json`（`CoreEngine.swift:86, 1070-1076`） | DataStore `zephyr` / key `settings_v0`（`SettingsStore.kt:23-24`） |
| mihomo 配置/控制口 | App Group `core/config.yaml`、`zm.sock`（`AppGroup.swift:34-41`） | 不落盘配置；`filesDir/mihomo/ctl.sock`（`TunBridge.kt` controllerSocket） |
| 共享摘要 | App Group SharedState（`schemaVersion = 1`，`SharedState.swift:10`） | 无（小组件/磁贴在进程内直接读引擎） |
| 本地代理凭据 | 钥匙串（含从 UserDefaults 迁移，`CoreEngine.swift:981-995`） | 明文文件 `core/local-proxy-credential`（`CoreEngine.kt:267`） |
| 生效订阅 | 无（取第一个） | `core/active-subscription` 文件 |

**E42（a+c，P2）**
- 迁移：iOS `Models.swift:615-627` 的 `Settings.init(from:)` 除 `localProxyEnabled` 外都用 `decode`（必填），而 `loadSettings` 解码失败时静默回落到默认（`CoreEngine.swift:1072-1073`）。以后契约追加任何设置字段，如果忘了写 `decodeIfPresent`，老用户的全部设置都会被重置。Android `ignoreUnknownKeys` 加 Kotlin 默认值，较宽松。建议 B 全部改用 `decodeIfPresent ?? 默认`，并加一个“旧版 JSON 能解码”的单测。
- 凭据：Android 明文存储，iOS 存钥匙串。建议 C 改用 EncryptedFile/Keystore（加固，非契约要求）。
- 首次默认值：iOS `CoreEngine.swift:1079-1083`（trustedWifi=[]、disconnectOnTrusted=false、shareAnonymousPattern=false）；Android `Model.kt:355-369`（trustedWifi=["家"]、disconnectOnTrusted=true、shareAnonymousPattern=**true**、localProxyAuth=true）。Android 的 Release 默认值直接用了 mock‑spec §6 的 Mock 值。契约只定义了“Mock 与首次启动一致”的 DNS/TUN（§13），其他字段没有 Release 默认值 → 契约缺口；隐私相关的 `shareAnonymousPattern` 默认值两端相反，建议 A 定为 false。

### J. 错误映射与用户可见错误态

**E43**：核心 `MobileError` → §10 `ErrorCode` 的映射

| MobileError | iOS（`CoreEngine.swift:138-149`） | Android（`CoreEngine.kt:774-783` + 场景调用 :528-530） | 判定 |
|---|---|---|---|
| NotFound | 由调用处决定 | 由调用处决定 | ✓ |
| SceneNotFound | scene_not_found ✓ | **internal**（`code()` 没有这个分支） | a，C |
| SubscriptionNotFound | **subscription_invalid** | subscription_not_found ✓ | a，B（v0.1 已加此码） |
| StaleToken | 重查失败时 **internal**（`CoreEngine.swift:576`） | stale_token ✓ | a，B |
| Invalid | rule_input_invalid（导入时改为 subscription_invalid，:729-732） | rule_input_invalid | c，A：§15.g 只说“平台映射到 §10”，没给对照表；Invalid 也会出现在 `setSceneNodeFilter`、`setFailoverPolicy`、导入载荷等非规则场景 |
| Io / Corrupt | internal | internal | c，A：Io 可能是 `storage_full` |
| NotRunning / Cancelled | ✓ | ✓ | ✓ |

用户可见的连接失败：iOS 以扩展写入的 `errorCode` 显示失败状态（`SystemTunnelPort.swift:133-139`）；Android 用 `connectError` 叠加在 DISCONNECTED 上显示为 FAILED（`CoreEngine.kt:786-797`）。机制不同（b），错误码差异见 E07。建议 A 在契约里补一张权威映射表，两端加单测。

### K. 小组件 / 实时活动 / 控制中心 vs Glance / QS 磁贴 / 常驻通知

| 面 | iOS | Android |
|---|---|---|
| 数据源 | App Group SharedState（App 与扩展写） | 进程内引擎流 |
| 主屏/锁屏小组件 | timeline 15 min + 零点条目（`SharedTimelineProvider.swift:17, 33-41`）；显著变化时 App 调 `reloadAllTimelines`；速率每 5 s 写盘不 reload；用量每 60 s（`SharedStatePublisher.swift:12-13`） | Glance，`updatePeriodMillis=0`；连接期间每 60 s `refreshAll`（`ZephyrWidget.kt:157`、`ZephyrVpnService.kt:108-111`），停止时刷新一次 |
| 实时/常驻 | Live Activity：连上即开始，更新 ≥5 s 且速率变化 ≥5%，`staleDate` 120 s（`LiveActivityController.swift:14`、`LiveActivityPolicy.swift`）；后台不能更新 | 前台服务通知：状态变化立即发；速率只在亮屏时、最少间隔 2 s 重发（`Notifications.kt:31`、`ZephyrVpnService.kt:97-99`）；在线时长用 chronometer |
| 快捷开关 | iOS 18 ControlWidget → `ConnectIntent`（扩展进程经 NETunnelProviderManager 启停） | QS 磁贴，监听期间实时；无授权时经 `VpnPermissionActivity` 中转 |
| 动作 | 连接/断开、切换模式（App Intents） | 通知：断开 / 全局↔规则；磁贴：开关；小组件：开关 |

刷新节奏和动作都符合各自平台的预算与惯例，与 §11“只读 ConnectionState、TrafficSample、场景摘要”一致（b，保留）。**E44 a 部分**：Android 小组件没有零点刷新，断开状态下过零点后“今日用量”会一直显示昨天的数据，直到下次刷新（C，P2）。iOS 扩展崩溃后的假“已连接”见 E05。

### L. 后台行为（汇总）

| 能力 | iOS（App 挂起，只有扩展在跑） | Android（前台服务常驻） |
|---|---|---|
| 流量/用量 | 扩展记账 ✓ | 服务记账 ✓ |
| 场景自动切换 | 后台不跑（E21） | 每 60 s |
| 服务/出口探测 | 不跑 | 约每 10 min（E25） |
| 订阅自动更新 | BGAppRefresh（系统决定时机，最早 4 h） | WorkManager 每小时 |
| 小组件刷新 | 依赖 App 写入 + 15 min timeline | 连接期间每 60 s |
| 实时活动/通知 | 实时活动 2 min 后标记过期 | 通知持续更新 |

差异来自 OS 后台模型（b）；建议 A 在契约 §11 加一张“后台能力矩阵”，免得被当作缺陷反复提出。

### M. 日志级别

两端 `RuntimeOptions.logLevel` 都写死 `"warning"`（iOS `CoreEngine.swift:968`，Android `CoreEngine.kt:256`），日志页选 debug/info 时 `zm_logs` 也拿不到更低级别的日志。增量拉取两端一致：1 Hz、seq 回退时从 0 重拉、limit 200 / 环形缓冲 500（iOS `CoreEngine+Live.swift:114-133`，Android `CoreEngine.kt:610-626`）✓。**E46（c，P2，A）**：契约应定义日志页级别与 mihomo `log-level` 是否联动（联动需要重载，可以只在打开日志页时临时提高）。平台自身日志：iOS 用 `os.Logger`（隐私标记较完整），Android 用 `android.util.Log`，属平台惯例。

### N. 其他

**E45 连接列表上限（a，P2，B）**：契约 §8 / MihomoClient 要求 `activeConnections` 最多 200；iOS `CoreEngine+Live.swift:180` 传 500（核心是否截断未验证）；Android 传 200（`CoreEngine.kt:657`）。

---

## 四、已核对一致的部分

- 控制口只用 unix socket（iOS App Group `zm.sock`，Android `filesDir/mihomo/ctl.sock`），核心 runtimeConfig 剔除 TCP 控制口和 secret ✓
- fake-ip 网段 198.18.0.1/16、tun 198.18.0.1/30、DNS 劫持到 198.18.0.2、v6 fdfe:dcba:9876::1/126 两端相同 ✓
- Release 不展示合成数据：两端都只在 `mockData`（Debug）时回落 MockEngine ✓（例外：E08）
- needsReload / selectInGroup / GLOBAL 组的处理顺序 ✓；AI 场景不自动切换 ✓
- TCP 握手测速参数 ✓；url-test URL 与超时 ✓；扫描每组 64、批 512 ✓
- `nodeRows` 遇到 StaleToken 时用原查询重查续页 ✓（只有 iOS 在丢失查询时的错误码不同）
- 规则集/GEO 在导入/更新后刷新，mrs 格式跳过、下载失败保留旧文件 ✓
- 内存压力：iOS `memoryPressure` → `zm_free_os_memory`；Android `onTrimMemory` → `trimMemory` ✓

## 五、局限与假设

- 全部为静态阅读结论，没有在设备上验证。E09 的 `system` 栈在 NE 里是否可用、E02 的重连行为、E04 的计费判定，都建议真机确认。
- “核心是否把 `activeConnections(limit: 500)` 截到 200”（E45）、mihomo `strict-route` 在 `auto-route=false` 下是否完全无效（E18）是根据代码和 mihomo 一般语义推断，没有逐行核对 mihomo-mobile 源码。
- 任务描述里的 Android “workers” 模块在仓库里不存在，对应实现是 `app/.../vpn/SubscriptionWorker.kt`，已按它审计。
- 本次只写了 `/workspace/work/audit/parity-engine.md`，仓库没有任何改动。
