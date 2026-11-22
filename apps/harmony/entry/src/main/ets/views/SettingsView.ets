/*
 * 设置（对照 Android ui/settings SettingsScreen，简化）：
 * - 连接：代理模式（engine.setMode）、按需连接、局域网不经代理（§16.a① 恒开、不可关闭，只作说明）；
 * - 检测：仅 Wi‑Fi 测速；
 * - 诊断：日志级别（AppServices.logs，与日志页共用）、日志页、共享诊断数据；
 * - 存储：节点 / 规则 / 可用；
 * - 外观：跟随系统 / 深色 / 浅色 + 强调色 4 种（§16.c，立即生效：EntryAbility 跟随设置流改色）；
 * - 关于：版本、引擎（演示 / 内置内核）、开源许可（占位页）。
 * 设置一律“读当前 → 改一项 → AppServices.settings.update 全量写回并落盘”；写失败时开关随状态流回弹并提示。
 * 暂未移植：受信任 Wi‑Fi、本地代理端口、DNS / TUN 高级项（v1 不展示）。
 */
import { bundleManager } from '@kit.AbilityKit';
import { AppServices } from '../app/AppServices';
import { MockEngine } from '../engine/MockEngine';
import { SceneFailoverNotice } from '../engine/Model';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZNavRow } from '../components/ZNavRow';
import { ZSection } from '../components/ZSection';
import { ZSegmented } from '../components/ZSegmented';
import { ZToggleRow } from '../components/ZToggleRow';
import { accentDark, accentLight, ZTheme } from '../common/Theme';
import { Accent, Appearance, ConnectionState, copySettings, LogLevel, ProxyMode, Settings, StorageInfo } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

const MODES: ProxyMode[] = [ProxyMode.RULE, ProxyMode.GLOBAL, ProxyMode.DIRECT];
const LEVELS: LogLevel[] = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR];
const APPEARANCES: Appearance[] = [Appearance.SYSTEM, Appearance.DARK, Appearance.LIGHT];
const ACCENTS: Accent[] = [Accent.BLUE, Accent.GREEN, Accent.ORANGE, Accent.PINK];

type SettingsPatch = (s: Settings) => void;

@ComponentV2
export struct SettingsView {
  @Event onOpenLogs: () => void = () => {};
  @Event onOpenLicenses: () => void = () => {};
  @Event onOpenTrustedWifi: () => void = () => {};
  @Event onOpenLocalProxy: () => void = () => {};

  @Local mode: ProxyMode = ProxyMode.RULE;
  @Local onDemand: boolean = true;
  @Local testOnWifiOnly: boolean = true;
  @Local shareDiagnostics: boolean = false;
  @Local appearance: Appearance = Appearance.SYSTEM;
  @Local accent: Accent = Accent.BLUE;
  @Local theme: ZTheme = ZTheme.shared();
  @Local logLevel: LogLevel = LogLevel.INFO;
  @Local storage: StorageInfo | undefined = undefined;
  @Local version: string = '';
  @Local trustedWifi: string[] = [];
  @Local localProxyEnabled: boolean = false;
  @Local localProxyPort: number = 7890;
  @Local localProxyAuth: boolean = true;

  private subs: StreamSub[] = [];

  aboutToAppear(): void {
    const svc = AppServices.get();
    this.subs.push(svc.engine.settings().subscribe((s: Settings) => {
      this.onDemand = s.onDemand;
      this.testOnWifiOnly = s.testOnWifiOnly;
      this.shareDiagnostics = s.shareDiagnostics;
      this.appearance = s.appearance;
      this.accent = s.accent;
      this.trustedWifi = s.trustedWifi.slice();
      this.localProxyEnabled = s.localProxyEnabled;
      this.localProxyPort = s.localProxyPort;
      this.localProxyAuth = s.localProxyAuth;
    }));
    this.subs.push(svc.engine.connectionState().subscribe((c: ConnectionState) => {
      this.mode = c.mode;
    }));
    this.subs.push(svc.logs.level.subscribe((l: LogLevel) => {
      this.logLevel = l;
    }));
    svc.engine.storage().then((s: StorageInfo) => {
      this.storage = s;
    }).catch(() => {});
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = info.versionName;
    } catch (e) {
      this.version = '';
    }
  }

  aboutToDisappear(): void {
    for (const s of this.subs) {
      s.cancel();
    }
    this.subs = [];
  }

  private patch(f: SettingsPatch): void {
    const svc = AppServices.get();
    const engine = svc.engine;
    const next = copySettings(engine.settings().value);
    f(next);
    svc.settings.update(next).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      // 回弹：重新读一次当前值。
      const cur = engine.settings().value;
      this.onDemand = cur.onDemand;
      this.testOnWifiOnly = cur.testOnWifiOnly;
      this.shareDiagnostics = cur.shareDiagnostics;
      this.appearance = cur.appearance;
      this.accent = cur.accent;
    });
  }

  private storageText(): ResourceStr {
    const s = this.storage;
    if (s === undefined) {
      return '';
    }
    return $r('app.string.settings_storage_detail', Format.bytesText(s.nodesBytes), Format.bytesText(s.rulesBytes),
      Format.bytesText(s.freeBytes));
  }

  private accentName(a: Accent): Resource {
    switch (a) {
      case Accent.GREEN:
        return $r('app.string.settings_accent_green');
      case Accent.ORANGE:
        return $r('app.string.settings_accent_orange');
      case Accent.PINK:
        return $r('app.string.settings_accent_pink');
      default:
        return $r('app.string.settings_accent_blue');
    }
  }

  /** 28vp 色点在 44vp 点按区内，选中描边 screen_t1；读屏按单选按钮朗读颜色名。 */
  @Builder
  accentDot(a: Accent) {
    Stack() {
      Circle()
        .width(28)
        .height(28)
        .fill(this.theme.isDark ? accentDark(a) : accentLight(a))
        .stroke(this.accent === a ? $r('app.color.screen_t1') : Color.Transparent)
        .strokeWidth(2)
    }
    .width(44)
    .height(44)
    .accessibilityText(this.accentName(a))
    .accessibilitySelected(this.accent === a)
    .onClick(() => {
      if (this.accent !== a) {
        this.accent = a;
        this.patch((s: Settings) => {
          s.accent = a;
        });
      }
    })
  }

  private simulateFailover(): void {
    const svc = AppServices.get();
    const engine = svc.engine;
    if (!(engine instanceof MockEngine)) {
      return;
    }
    engine.simulateFailover().then((n: SceneFailoverNotice | undefined) => {
      if (n === undefined) {
        try {
          svc.toasts.show(this.getUIContext().getHostContext()!.resourceManager
            .getStringSync($r('app.string.hm_settings_mock_failover_offline').id));
        } catch (e) {
          // 资源取不到时静默
        }
      }
    }).catch(() => {});
  }

  private engineLabel(): Resource {
    return AppServices.get().engine.kind === 'mock' ? $r('app.string.hm_settings_engine_mock')
      : $r('app.string.hm_settings_engine_native');
  }

  build() {
    Scroll() {
      // 标题由外层 NavDestination 给（Index 路由 settings）。
      Column({ space: 20 }) {
        ZSection({ header: $r('app.string.settings_section_connection'), footer: $r('app.string.hm_settings_lan_bypass_footer') }) {
          Column({ space: 6 }) {
            Text($r('app.string.hm_settings_mode'))
              .fontSize(16)
              .fontColor($r('app.color.screen_t1'))
            ZSegmented({
              options: [Labels.mode(ProxyMode.RULE), Labels.mode(ProxyMode.GLOBAL), Labels.mode(ProxyMode.DIRECT)],
              selected: MODES.indexOf(this.mode),
              onSelect: (i: number) => {
                AppServices.get().engine.setMode(MODES[i]).catch(() => {});
              }
            })
            Text(Labels.modeHint(this.mode))
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          ZToggleRow({
            title: $r('app.string.settings_on_demand'),
            isOn: this.onDemand,
            onChange: (on: boolean) => {
              this.onDemand = on;
              this.patch((s: Settings) => {
                s.onDemand = on;
              });
            }
          })
          ZNavRow({
            title: $r('app.string.settings_trusted_wifi'),
            value: this.trustedWifi.length > 0 ? this.trustedWifi.join(', ') : ZTerm.none,
            onTap: () => this.onOpenTrustedWifi()
          })
          ZNavRow({
            title: ZTerm.localProxyPort,
            value: this.localProxyEnabled ? ZTerm.on : ZTerm.off,
            onTap: () => this.onOpenLocalProxy()
          })
          ZToggleRow({ title: $r('app.string.hm_settings_lan_bypass'), isOn: true, isEnabled: false, divider: false })
        }

        ZSection({ header: $r('app.string.settings_section_testing') }) {
          ZToggleRow({
            title: $r('app.string.settings_test_wifi_only'),
            isOn: this.testOnWifiOnly,
            divider: false,
            onChange: (on: boolean) => {
              this.testOnWifiOnly = on;
              this.patch((s: Settings) => {
                s.testOnWifiOnly = on;
              });
            }
          })
        }

        ZSection({ header: ZTerm.diagnostics }) {
          Column({ space: 6 }) {
            Text($r('app.string.hm_settings_log_level'))
              .fontSize(16)
              .fontColor($r('app.color.screen_t1'))
            ZSegmented({
              options: [Labels.logLevel(LogLevel.DEBUG), Labels.logLevel(LogLevel.INFO), Labels.logLevel(LogLevel.WARNING),
                Labels.logLevel(LogLevel.ERROR)],
              selected: LEVELS.indexOf(this.logLevel),
              onSelect: (i: number) => AppServices.get().logs.setLevel(LEVELS[i])
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          ZNavRow({ title: ZTerm.logs, onTap: () => this.onOpenLogs() })
          ZToggleRow({
            title: $r('app.string.settings_share_diagnostics'),
            isOn: this.shareDiagnostics,
            divider: false,
            onChange: (on: boolean) => {
              this.shareDiagnostics = on;
              this.patch((s: Settings) => {
                s.shareDiagnostics = on;
              });
            }
          })
        }

        ZSection({ header: $r('app.string.settings_section_storage'), footer: $r('app.string.settings_local_data_note') }) {
          ZNavRow({ title: $r('app.string.settings_storage_title'), value: this.storageText(), chevron: false, divider: false })
        }

        ZSection({ header: ZTerm.appearance }) {
          Column({ space: 6 }) {
            ZSegmented({
              options: [ZTerm.appearanceSystem, ZTerm.appearanceDark, ZTerm.appearanceLight],
              selected: APPEARANCES.indexOf(this.appearance),
              onSelect: (i: number) => {
                const a = APPEARANCES[i];
                this.appearance = a;
                this.patch((s: Settings) => {
                  s.appearance = a;
                });
              }
            })
          }
          .width('100%')
          .padding(16)
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          Row() {
            Text(ZTerm.accent)
              .fontSize(16)
              .fontColor($r('app.color.screen_t1'))
              .layoutWeight(1)
            ForEach(ACCENTS, (a: Accent) => {
              this.accentDot(a)
            }, (a: Accent) => a as string)
          }
          .width('100%')
          .padding({ left: 16, right: 6, top: 4, bottom: 4 })
        }

        ZSection({ header: $r('app.string.settings_section_about') }) {
          ZNavRow({ title: $r('app.string.hm_settings_version'), value: this.version, chevron: false })
          ZNavRow({ title: $r('app.string.hm_settings_engine'), value: this.engineLabel(), chevron: false })
          if (AppServices.get().engine.kind === 'mock') {
            // 仅演示引擎：触发一次场景故障切换，供首页「已切换」卡片和撤销在真机 / 云调试上验证（M1-6）。
            ZNavRow({ title: $r('app.string.hm_settings_mock_failover'), onTap: () => this.simulateFailover() })
          }
          ZNavRow({ title: $r('app.string.settings_licenses'), divider: false, onTap: () => this.onOpenLicenses() })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
