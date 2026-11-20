/*
 * 设置（对照 Android ui/settings SettingsScreen，简化）：
 * - 连接：代理模式（engine.setMode）、按需连接、局域网不经代理（§16.a① 恒开、不可关闭，只作说明）；
 * - 检测：仅 Wi‑Fi 测速；
 * - 诊断：日志级别（AppServices.logs，与日志页共用）、日志页、共享诊断数据；
 * - 存储：节点 / 规则 / 可用；
 * - 关于：版本、引擎（演示 / 内置内核）、开源许可（占位页）。
 * 设置一律“读当前 → 改一项 → updateSettings 全量写回”；写失败时开关随状态流回弹并提示。
 * 暂未移植：受信任 Wi‑Fi、本地代理端口、外观 / 强调色、DNS / TUN 高级项。
 */
import { bundleManager } from '@kit.AbilityKit';
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZNavRow } from '../components/ZNavRow';
import { ZSection } from '../components/ZSection';
import { ZSegmented } from '../components/ZSegmented';
import { ZToggleRow } from '../components/ZToggleRow';
import { ConnectionState, copySettings, LogLevel, ProxyMode, Settings, StorageInfo } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

const MODES: ProxyMode[] = [ProxyMode.RULE, ProxyMode.GLOBAL, ProxyMode.DIRECT];
const LEVELS: LogLevel[] = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR];

type SettingsPatch = (s: Settings) => void;

@ComponentV2
export struct SettingsView {
  @Event onOpenLogs: () => void = () => {};
  @Event onOpenLicenses: () => void = () => {};

  @Local mode: ProxyMode = ProxyMode.RULE;
  @Local onDemand: boolean = true;
  @Local testOnWifiOnly: boolean = true;
  @Local shareDiagnostics: boolean = false;
  @Local logLevel: LogLevel = LogLevel.INFO;
  @Local storage: StorageInfo | undefined = undefined;
  @Local version: string = '';

  private subs: StreamSub[] = [];

  aboutToAppear(): void {
    const svc = AppServices.get();
    this.subs.push(svc.engine.settings().subscribe((s: Settings) => {
      this.onDemand = s.onDemand;
      this.testOnWifiOnly = s.testOnWifiOnly;
      this.shareDiagnostics = s.shareDiagnostics;
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
    const engine = AppServices.get().engine;
    const next = copySettings(engine.settings().value);
    f(next);
    engine.updateSettings(next).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      // 回弹：重新读一次当前值。
      const cur = engine.settings().value;
      this.onDemand = cur.onDemand;
      this.testOnWifiOnly = cur.testOnWifiOnly;
      this.shareDiagnostics = cur.shareDiagnostics;
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

  private engineLabel(): Resource {
    return AppServices.get().engine.kind === 'mock' ? $r('app.string.hm_settings_engine_mock')
      : $r('app.string.hm_settings_engine_native');
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Text(ZTerm.settings)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.screen_t1'))

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

        ZSection({ header: $r('app.string.settings_section_about') }) {
          ZNavRow({ title: $r('app.string.hm_settings_version'), value: this.version, chevron: false })
          ZNavRow({ title: $r('app.string.hm_settings_engine'), value: this.engineLabel(), chevron: false })
          ZNavRow({ title: $r('app.string.settings_licenses'), divider: false, onTap: () => this.onOpenLicenses() })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 24, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
