# 发布清单（Zephyr Mobile v1.0）

> 依据：发版前审计 `docs/audit/2026-11-18-release.md`（PR #206），跟踪 issue #209。
> 标 **【待用户决定】** 的项需要仓库所有者拍板，agent 不能代为决定；标 **【待用户提供】** 的项需要账号或密钥。
> 本文是清单 + 步骤，随实现推进更新；已完成的项打勾并注明 PR。

## 0. 待用户决定 / 提供（阻塞项汇总）

| # | 事项 | 影响 | 状态 |
|---|---|---|---|
| D1 | **许可证**（用户 2026-11-18 确认）：自有源码 MIT（根目录 `LICENSE`）；`mihomo-mobile/LICENSE` 为 GPL-3.0；移动端安装包因静态链接 mihomo 整体按 GPL-3.0 分发，对应源码 = 本仓库对应 tag | App 内“开源许可”页、发布时指明源码 tag | ✅ 已定（#219） |
| D2 | **Apple 开发者团队**：必须是付费**组织**账号（App Store 审核指南 5.4：VPN App 须由组织发布），提供 Team ID | `apps/ios/project.yml` 的 `DEVELOPMENT_TEAM`（现为空）、描述文件 | 【待用户提供】 |
| D3 | **应用标识统一**为 `com.juwanh.zephyr`，App Group `group.com.juwanh.zephyr`（用户 2026-11-18 确认）。现状：iOS `app.zephyr.mobile*` / `group.app.zephyr.mobile`，Android `com.zephyr.app`，需由 B/C 改到新标识（上架后不可更改） | 两端工程、Play/App Store 后台、App Group | ✅ 已定；待 B/C 改工程 |
| D4 | **中国大陆区**：大陆 App Store 的 VPN App 需持牌，是否在 App Store Connect 排除中国大陆店面 | 上架地区 | 【待用户决定】 |
| D5 | **Android 上传密钥**：生成 upload keystore，并放进 GitHub Actions secrets；是否启用 Play App Signing（建议启用） | Release 签名 | 【待用户提供】 |
| D6 | **App Store Connect / Play Console 账号**与开发者主体信息、隐私政策 URL、支持 URL | 上架资料 | 【待用户提供】 |
| D7 | Android 前台服务类型：沿用 `specialUse`（需提交 FGS 声明）还是评估 `systemExempted` | Play 审核 | 【待用户决定】（C 评估） |

## 1. 版本号规则

- **版本名**：两端统一 `1.0.0`。iOS `MARKETING_VERSION`（`apps/ios/project.yml`）；Android `versionName`（`apps/android/app/build.gradle.kts`，现为 `1.0`，由 C 改为 `1.0.0`）。
- **构建号**：由 CI 注入，取 GitHub Actions `run_number`（单调递增，两端同一次 run 相同）：
  - iOS：`xcodebuild … CURRENT_PROJECT_VERSION=${{ github.run_number }}`（App / PacketTunnel / Widgets 三个 target 都读 `$(CURRENT_PROJECT_VERSION)`，扩展与 App 构建号必须一致）。
  - Android：`-Pzephyr.versionCode=${{ github.run_number }}`，`app/build.gradle.kts` 读取后覆盖 `versionCode`（由 C 接入）。
  - 本地构建保留仓库里的默认值 `1`，不能用于上传。
  - CI 注入由 PR #210 实现（进行中）。
- 后续版本：功能版本升 minor（1.1.0），修复升 patch（1.0.1）；构建号只增不减，不要手改。

## 2. 签名

### iOS
- [ ] 【待用户提供】组织账号 Team ID → 写入 `project.yml` 的 `DEVELOPMENT_TEAM`（B）。
- [ ] B：`project.yml` 的 bundle ID 与 App Group 改为 D3 定下的标识（`bundleIdPrefix`、各 target `PRODUCT_BUNDLE_IDENTIFIER`、`ZEPHYR_APP_GROUP`、三份 entitlements）。
- [ ] 在 Apple Developer 后台注册 3 个 App ID：`com.juwanh.zephyr`、`com.juwanh.zephyr.PacketTunnel`、`com.juwanh.zephyr.Widgets`，每个都开启：
  - **Network Extensions**（Packet Tunnel Provider）——Widgets 也需要（控制中心开关会启动隧道，见 `Widgets/ZephyrWidgets.entitlements`）；
  - **App Groups**：`group.com.juwanh.zephyr`（App、PacketTunnel、Widgets 三者共用）。
- [ ] 生成 Distribution 证书与 3 个 App Store 描述文件；CI 若做自动上传，证书 p12、描述文件、App Store Connect API Key 放进 GitHub secrets（发布流水线骨架见审计 R P0-2，待签名材料到位后由 A 实现）。
- [ ] Archive：`xcodebuild archive -configuration Release -sdk iphoneos`，用 Xcode Organizer 或 `xcodebuild -exportArchive` 导出并上传。

### Android
- [ ] C：`applicationId` 改为 `com.juwanh.zephyr`（`namespace` 可保持不变，只影响代码包名）。
- [ ] 【待用户提供】upload keystore，存为 secrets（建议名：`ANDROID_UPLOAD_KEYSTORE_BASE64`、`ANDROID_UPLOAD_KEYSTORE_PASSWORD`、`ANDROID_UPLOAD_KEY_ALIAS`、`ANDROID_UPLOAD_KEY_PASSWORD`）。
- [ ] C：`release` 的 `signingConfig` 改为从环境变量 / keystore 读取（现为 debug 签名，`app/build.gradle.kts`），无密钥时 CI 仍能构建未签名包。
- [ ] 启用 Play App Signing，上传 AAB（`bundleRelease`）。
- 密钥绝不入库；本地发布构建用 `~/.gradle/gradle.properties` 或环境变量。

## 3. 构建门槛（发布前 CI 必须全绿）

- [ ] `libzmihomo.so` 16 KB 页对齐（`-extldflags=-Wl,-z,max-page-size=16384`），CI 传 `-Pzephyr.strict16k=true` 使未对齐即失败（PR #210）。
- [ ] iOS `Release` + `-sdk iphoneos` + `CODE_SIGNING_ALLOWED=NO` 构建通过（覆盖非 DEBUG 分支、`-O`、真机 arm64 链接）（PR #210）。
- [ ] Android `assembleRelease` / `bundleRelease`（R8 + JNA/UniFFI keep 规则）通过（PR #210）。
- [ ] contract / core / ios / android 四个 job 全绿。

## 4. Google Play

- [ ] **16 KB 页大小**：targetSdk ≥ 35 的新应用/更新要求所有 `.so` 16 KB 对齐（见 §3）。上传前用 `zipalign -c -P 16 -v 4` 或 Android Studio APK Analyzer 复核 AAB 产物。
- [ ] **前台服务声明**：`ZephyrVpnService` 用 `foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`，须在 Play Console「应用内容 › 前台服务权限」提交 specialUse 声明（说明用途并附操作视频）（D7）。
- [ ] **VpnService 政策声明**：在 Play Console 声明 VPN 是应用核心功能，说明不收集/出售用户流量数据、遵守设备与网络滥用政策。
- [ ] 数据安全表单（与隐私政策一致）、内容分级、目标受众。
- [ ] 通知权限（`POST_NOTIFICATIONS`）、开机自启（`RECEIVE_BOOT_COMPLETED`）的用途在商店说明里写清。
- [ ] 先走内部测试轨道，再封闭测试，再正式。

## 5. App Store

- [ ] **审核指南 5.4**：VPN App 必须由组织账号发布，使用 `NEVPNManager` / NetworkExtension，不得出售/披露用户数据（D2）。
- [ ] **出口合规**：`ITSAppUsesNonExemptEncryption = true`（如实声明，App 含非豁免加密），需在 App Store Connect 完成出口合规问卷，按问卷结果准备所需文件（如美国 BIS 年度自我分类报告；是否需要法国加密申报以问卷提示为准）。
- [ ] **中国大陆店面**：大陆区 VPN App 需持牌，未取得前在「价格与销售范围」排除中国大陆（D4）。
- [ ] 隐私：三个 target 的 `PrivacyInfo.xcprivacy` 已齐（审计已核对）；App Store Connect「App 隐私」问卷与之一致。
- [ ] 审核备注：说明 VPN 用途、提供测试订阅（审核员可用的配置 URL）和操作步骤。
- [ ] 截图（6.9"/6.5" iPhone）、描述、关键词、支持 URL、隐私政策 URL（D6）。
- [ ] 先 TestFlight 内测，再提交审核。

## 6. 许可与第三方声明

- [ ] 根目录 `LICENSE`（MIT）与 `mihomo-mobile/LICENSE`（GPL-3.0）入库（#219）。
- [ ] `THIRD_PARTY_NOTICES.md`：Rust（含 MPL-2.0 的 uniffi*，须附许可文本）与 Go（mihomo GPL-3.0 等）运行时依赖清单，由 `tools/gen-third-party.sh` 生成；依赖升级后重新生成。
- [ ] B/C：设置 › 关于 › 开源许可页面，展示上述清单与许可全文。
- [ ] 安装包按 GPL-3.0 分发：App 名不含 “mihomo”；商店描述 / 关于页注明许可与源码地址，对应源码即本仓库该版本的 tag（含子模块 commit 与 `mihomo-mobile/go.sum` 锁定版本）。

## 7. 真机验证清单（模拟器 / 沙箱无法覆盖）

iOS（B）：
- [ ] PacketTunnel 内存：NE 进程上限 50 MB，在大订阅（≥10 万节点）+ 长时间连接下不超限（Xcode Memory Gauge / Instruments）。
- [ ] Release 真机构建能链接并加载 Zmihomo 与 Rust 静态库，冷启动不崩。
- [ ] 真实 VPN 流量：连接、断开、切换场景、模式切换、断网重连、Wi‑Fi ↔ 蜂窝切换、睡眠唤醒。
- [ ] 按需连接 / 受信任 Wi‑Fi 行为。
- [ ] 小组件、锁屏实时活动 / 灵动岛、控制中心开关能启停隧道。
- [ ] 冷启动 < 1 s；节点列表滚动 60fps（ProMotion 设备 120fps）。

Android（C）：
- [ ] 16 KB 页设备（或 16 KB 模拟器镜像）上能加载 `libzephyr_mobile_core.so` 与 `libzmihomo.so`。
- [ ] Release（R8）包启动、连接、UniFFI 调用不因混淆失败。
- [ ] 真实 VPN 流量（同 iOS 列表），常驻通知、快速设置磁贴、Glance 小组件、开机自启。
- [ ] 中端机冷启动 < 1 s、节点列表 2000 行滚动 60fps。
- [ ] Android 13+ 通知权限拒绝时的行为。

两端结果由 A 汇总进 `docs/perf.md`（审计 R P1-5）。

## 8. 发布步骤

1. 确认 §0 阻塞项均已解决，§3 门槛全绿，§7 真机清单全部通过并记录。
2. main 上确认版本名 `1.0.0`，在看板 #1 宣布冻结。
3. 由 A 在 main 的发布提交上打 tag 并推送：
   ```sh
   git tag -a mobile-v1.0 -m "Zephyr Mobile v1.0"
   git push origin mobile-v1.0
   ```
4. 用该 tag 对应的 CI run（构建号 = run_number）产出签名 IPA / AAB，上传 TestFlight 与 Play 内部测试。
5. 内测通过后提交 App Store 审核、Play 推进到正式轨道。
6. 在 GitHub Releases 发布说明，附第三方许可清单（若按 GPL 分发，附源码获取方式）。
7. 看板 #1 汇总，关闭 #209 中已完成项。
