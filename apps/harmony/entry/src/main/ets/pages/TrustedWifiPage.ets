import { LengthMetrics } from '@kit.ArkUI';
/*
 * 设置 › 受信任的 Wi‑Fi（M1-14；对照 Android LibraryPages TrustedWifiScreen / iOS TrustedWifiView）：
 * “连上这些 Wi‑Fi 时自动断开”开关、网络列表（每行“删除”）、添加输入框（1–32 字节、不重复、最多 50 个）。
 * 只读写 Settings；按 SSID 自动断开由连接层负责（M4，读 SSID 需 GET_WIFI_INFO，已声明）。
 */
import { AppServices } from '../app/AppServices';
import { TrustedWifi } from '../app/NetworkPrefs';
import { ZSection } from '../components/ZSection';
import { ZToggleRow } from '../components/ZToggleRow';
import { copySettings, Settings } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTheme } from '../common/Theme';
import { ZTerm } from '../generated/ZTerms';

export const TRUSTED_WIFI_INPUT_ID: string = 'zephyr.trustedWifi.input';
export const TRUSTED_WIFI_ADD_ID: string = 'zephyr.trustedWifi.add';

@ComponentV2
export struct TrustedWifiPage {
  @Local list: string[] = [];
  @Local disconnect: boolean = true;
  @Local name: string = '';
  @Local theme: ZTheme = ZTheme.shared();
  private sub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    this.sub = AppServices.get().engine.settings().subscribe((s: Settings) => {
      this.list = s.trustedWifi.slice();
      this.disconnect = s.disconnectOnTrusted;
    });
  }

  aboutToDisappear(): void {
    if (this.sub !== undefined) {
      this.sub.cancel();
      this.sub = undefined;
    }
  }

  private current(): Settings {
    return AppServices.get().engine.settings().value;
  }

  private canAdd(): boolean {
    return TrustedWifi.add(this.current(), this.name) !== undefined;
  }

  private write(next: Settings): void {
    AppServices.get().settings.update(next).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      const cur = this.current();
      this.list = cur.trustedWifi.slice();
      this.disconnect = cur.disconnectOnTrusted;
    });
  }

  private add(): void {
    const next = TrustedWifi.add(this.current(), this.name);
    if (next !== undefined) {
      this.name = '';
      this.write(next);
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 20 }) {
          ZSection({ footer: $r('app.string.trusted_wifi_footer') }) {
            ZToggleRow({
              title: $r('app.string.trusted_wifi_disconnect'),
              isOn: this.disconnect,
              divider: false,
              onChange: (on: boolean) => {
                this.disconnect = on;
                const next = copySettings(this.current());
                next.disconnectOnTrusted = on;
                this.write(next);
              }
            })
          }
          ZSection({ header: $r('app.string.trusted_wifi_networks') }) {
            ForEach(this.list, (ssid: string) => {
              Column() {
                Row() {
                  Text(ssid)
                    .fontSize(16)
                    .fontColor($r('app.color.screen_t1'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button(ZTerm.delete)
                    .fontSize(14)
                    .height(32)
                    .fontColor($r('app.color.screen_red_text'))
                    .backgroundColor(Color.Transparent)
                    .onClick(() => this.write(TrustedWifi.remove(this.current(), ssid)))
                }
                .width('100%')
                .height(52)
                .padding({ start: LengthMetrics.vp(16), end: LengthMetrics.vp(8) })
                Divider().strokeWidth(1).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(16) })
              }
            }, (ssid: string) => ssid)
            Row() {
              TextInput({ text: this.name, placeholder: $r('app.string.trusted_wifi_add_hint') })
                .id(TRUSTED_WIFI_INPUT_ID)
                .layoutWeight(1)
                .height(44)
                .fontSize(16)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.screen_t1'))
                .enterKeyType(EnterKeyType.Done)
                .onChange((v: string) => {
                  this.name = v;
                })
                .onSubmit(() => this.add())
              Button($r('app.string.common_add'))
                .id(TRUSTED_WIFI_ADD_ID)
                .fontSize(14)
                .height(32)
                .fontColor(this.canAdd() ? this.theme.accentColor() : $r('app.color.screen_t3'))
                .backgroundColor(Color.Transparent)
                .enabled(this.canAdd())
                .onClick(() => this.add())
            }
            .width('100%')
            .padding({ start: LengthMetrics.vp(4), end: LengthMetrics.vp(8) })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title($r('app.string.settings_trusted_wifi'))
    .backgroundColor($r('app.color.screen_bg'))
  }
}
