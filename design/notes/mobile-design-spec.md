# Zephyr 移动端设计规范 v0.1（草案，2026-11-06）

原则：保留桌面端的气质，移动端 UI 和 UX 全部重写。原生 SwiftUI + Compose。token 只认主仓库 Zephyr main 的 `packages/tokens`。

## 1. 从桌面继承的气质
- **深色优先的玻璃质感**：深色是默认（`value`），浅色是覆盖层（`lightValue`）；层次靠半透明表面和 1px 细边框分出来，不靠重阴影。
- **克制的强调色**：Apple 系统色，blue `#007AFF`（默认）/ green / orange / pink。紫色已经在主仓库里去掉了（#1624），zephyr-mobile 安卓端还默认用紫色，这就是分叉的例子。
- **文字层级用透明度表达**：primary 95%、secondary 60%、tertiary 40%。
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

## 3. 信息架构（桌面 9 页 → 手机 4 Tab）
| Tab | 内容 | 来自桌面 |
|---|---|---|
| 首页 | 连接开关、当前节点、模式切换、实时流量、今日用量、活跃连接摘要 | home、connections（摘要） |
| 代理 | 策略组 → 节点列表、选择节点、测延迟、隐藏超时节点 | proxies |
| 配置 | 订阅与配置文件、扫码/URL/剪贴板导入、更新、覆写、规则库 | subscriptions、advanced、rule-library |
| 设置 | 主题与强调色、DNS、TUN/VPN 选项、日志、连接详情、关于 | settings、logs、connections（完整） |
- 桌面的控制台（console）手机端不做，或者放进设置 › 开发者。

## 4. 关键页面
- **首页**：中间一个大连接按钮（ZConnectButton），状态变化用 spring 动效加轻微光晕（accent glow）；下面是当前节点卡、规则/全局/直连分段控件、实时上下行（细字大数字加迷你曲线）。
- **代理**：策略组卡片列表，点进去是节点列表；节点行显示国旗、名称、延迟胶囊（颜色按延迟分档）；下拉整组测速，点一下切换，带触感反馈。
- **配置**：订阅卡显示流量用量条和到期时间；右上角“+”打开导入面板（扫码、URL、剪贴板、文件）；左滑可更新或删除。
- **设置**：分组列表，iOS 是 inset grouped 风格，Android 用自绘卡片分组，两端视觉一致。

## 5. 平台习惯（保持气质一致，交互跟随平台）
| 项 | iOS | Android |
|---|---|---|
| 底部导航 | TabView + 材质背景 | 自绘玻璃底栏（不用 M3 胶囊指示器） |
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
1. 用户确认 IA 和气质描述
2. 落地 `mobile.json` 并调整 config.js 输出路径
3. 先做组件库和首页，两端同步
