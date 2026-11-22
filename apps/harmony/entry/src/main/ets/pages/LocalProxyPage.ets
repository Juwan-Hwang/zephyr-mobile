import { LengthMetrics } from '@kit.ArkUI';
/*
 * 设置 › 本地代理端口（M1-14；对照 Android LibraryPages LocalProxyScreen，契约 §16.c / §16.g①）：
 * 开关、端口（1024–65535，点“应用”才写）、需要密码；开着密码时显示连接信息：用户名 zephyr、密码（点按显示 / 隐藏）、
 * 复制 HTTP / SOCKS5 地址（剪贴板只留本机，不跨设备同步）、重新生成密码。写入失败提示“未能应用更改”。
 * 凭据只放内存，不进持久化状态。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { AppServices } from '../app/AppServices';
import { LocalProxy, PROXY_PORT_MAX, PROXY_PORT_MIN } from '../app/NetworkPrefs';
import { ZNavRow } from '../components/ZNavRow';
import { ZSection } from '../components/ZSection';
import { ZToggleRow } from '../components/ZToggleRow';
import { copySettings, Settings } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTheme } from '../common/Theme';
import { ZTerm } from '../generated/ZTerms';

export const LOCAL_PROXY_PORT_ID: string = 'zephyr.localProxy.port';
export const LOCAL_PROXY_APPLY_ID: string = 'zephyr.localProxy.apply';
export const LOCAL_PROXY_PASSWORD_ID: string = 'zephyr.localProxy.password';

const MASK: string = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

@ComponentV2
export struct LocalProxyPage {
  @Local proxyOn: boolean = false;
  @Local auth: boolean = true;
  @Local savedPort: number = 7890;
  @Local port: string = '';
  @Local edited: boolean = false;
  @Local credential: string | undefined = undefined;
  @Local reveal: boolean = false;
  @Local busy: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private sub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    const engine = AppServices.get().engine;
    this.sub = engine.settings().subscribe((s: Settings) => {
      this.proxyOn = s.localProxyEnabled;
      this.auth = s.localProxyAuth;
      this.savedPort = s.localProxyPort;
      if (!this.edited) {
        this.port = String(s.localProxyPort);
      }
    });
    engine.localProxyCredential().then((c: string) => {
      this.credential = c;
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.sub !== undefined) {
      this.sub.cancel();
      this.sub = undefined;
    }
    this.credential = undefined;
  }

  private toast(r: Resource): void {
    this.getUIContext().getPromptAction().showToast({ message: r, duration: 2000 });
  }

  private apply(f: (s: Settings) => void): void {
    const next = copySettings(AppServices.get().engine.settings().value);
    f(next);
    AppServices.get().settings.update(next).catch(() => {
      this.toast($r('app.string.local_proxy_apply_failed'));
      const cur = AppServices.get().engine.settings().value;
      this.proxyOn = cur.localProxyEnabled;
      this.auth = cur.localProxyAuth;
    });
  }

  private parsed(): number | undefined {
    return LocalProxy.parsePort(this.port);
  }

  private save(): void {
    const p = this.parsed();
    if (p === undefined) {
      return;
    }
    this.edited = false;
    if (p !== this.savedPort) {
      this.apply((s: Settings) => {
        s.localProxyPort = p;
      });
    }
  }

  private copy(scheme: string): void {
    const c = this.credential;
    if (c === undefined) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, LocalProxy.url(scheme, c, this.savedPort));
      const props = data.getProperty();
      props.shareOption = pasteboard.ShareOption.LOCALDEVICE;
      data.setProperty(props);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast($r('app.string.local_proxy_copied'));
      }).catch(() => {});
    } catch (e) {
      // 剪贴板不可用：不提示成功
    }
  }

  private regenerate(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const engine = AppServices.get().engine;
    engine.resetLocalProxyCredential().then((c: string) => {
      this.credential = c;
      this.toast($r('app.string.local_proxy_regenerated'));
    }).catch(() => {
      this.toast($r('app.string.local_proxy_apply_failed'));
      engine.localProxyCredential().then((c: string) => {
        this.credential = c;
      }).catch(() => {});
    }).finally(() => {
      this.busy = false;
    });
  }

  private shown(): string {
    const c = this.credential;
    return c === undefined ? '' : (this.reveal ? LocalProxy.password(c) : MASK);
  }

  @Builder
  copyRow(scheme: string, title: Resource, divider: boolean) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontColor(this.theme.accentColor())
      // \u2066…\u2069：阿拉伯语 / 波斯语 / 乌尔都语里保持地址从左到右。
      Text('\u2066' + LocalProxy.url(scheme, LocalProxy.USER + ':' + this.shown(), this.savedPort) + '\u2069')
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t3'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .border(divider ? { width: { bottom: 0.5 }, color: $r('app.color.screen_hl') } : { width: 0 })
    .onClick(() => this.copy(scheme))
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 20 }) {
          ZSection({ footer: $r('app.string.local_proxy_footer') }) {
            ZToggleRow({
              title: ZTerm.localProxyPort,
              isOn: this.proxyOn,
              divider: false,
              onChange: (on: boolean) => {
                this.proxyOn = on;
                this.apply((s: Settings) => {
                  s.localProxyEnabled = on;
                });
              }
            })
          }

          ZSection({ header: $r('app.string.local_proxy_port'), footer: $r('app.string.local_proxy_port_footer') }) {
            Row() {
              TextInput({ text: this.port, placeholder: $r('app.string.local_proxy_port') })
                .id(LOCAL_PROXY_PORT_ID)
                .type(InputType.Number)
                .layoutWeight(1)
                .height(44)
                .fontSize(16)
                .fontFamily('monospace')
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.screen_t1'))
                .enterKeyType(EnterKeyType.Done)
                .onChange((v: string) => {
                  const d = LocalProxy.digits(v);
                  this.port = d;
                  this.edited = true;
                })
                .onSubmit(() => this.save())
              Button(ZTerm.apply)
                .id(LOCAL_PROXY_APPLY_ID)
                .fontSize(14)
                .height(32)
                .backgroundColor(Color.Transparent)
                .fontColor(this.parsed() !== undefined && this.parsed() !== this.savedPort
                  ? this.theme.accentColor() : $r('app.color.screen_t3'))
                .enabled(this.parsed() !== undefined && this.parsed() !== this.savedPort)
                .onClick(() => this.save())
            }
            .width('100%')
            .padding({ start: LengthMetrics.vp(4), end: LengthMetrics.vp(8) })
            if (this.port.length > 0 && this.parsed() === undefined) {
              Text($r('app.string.local_proxy_port_invalid', PROXY_PORT_MIN, PROXY_PORT_MAX))
                .fontSize(13)
                .fontColor($r('app.color.screen_amber_text'))
                .width('100%')
                .padding({ left: 16, right: 16, top: 4, bottom: 12 })
            }
          }

          ZSection({ header: $r('app.string.local_proxy_security'), footer: $r('app.string.local_proxy_auth_footer') }) {
            ZToggleRow({
              title: ZTerm.requirePassword,
              isOn: this.auth,
              divider: false,
              onChange: (on: boolean) => {
                this.auth = on;
                this.apply((s: Settings) => {
                  s.localProxyAuth = on;
                });
              }
            })
          }

          if (this.auth && this.credential !== undefined) {
            ZSection({ header: $r('app.string.local_proxy_credentials') }) {
              ZNavRow({ title: $r('app.string.local_proxy_user_row'), value: LocalProxy.USER, chevron: false })
              Row() {
                Text($r('app.string.local_proxy_credential_row'))
                  .fontSize(16)
                  .fontColor($r('app.color.screen_t1'))
                Blank()
                Text(this.shown())
                  .fontSize(14)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.screen_t3'))
                  .maxLines(1)
                  .accessibilityText(this.reveal ? this.shown() : this.str($r('app.string.local_proxy_concealed')))
              }
              .id(LOCAL_PROXY_PASSWORD_ID)
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .border({ width: { bottom: 0.5 }, color: $r('app.color.screen_hl') })
              .accessibilityDescription(this.reveal ? this.str($r('app.string.local_proxy_conceal'))
                : this.str($r('app.string.local_proxy_reveal')))
              .onClick(() => {
                this.reveal = !this.reveal;
              })
              this.copyRow('http', $r('app.string.local_proxy_copy_http'), true)
              this.copyRow('socks5', $r('app.string.local_proxy_copy_socks'), false)
            }
            ZSection({ footer: $r('app.string.local_proxy_regenerate_footer') }) {
              ZNavRow({
                title: $r('app.string.local_proxy_regenerate'),
                chevron: false,
                divider: false,
                onTap: () => this.regenerate()
              })
            }
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
    .title(ZTerm.localProxyPort)
    .backgroundColor($r('app.color.screen_bg'))
  }

  private str(r: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id) : '';
    } catch (e) {
      return '';
    }
  }
}
