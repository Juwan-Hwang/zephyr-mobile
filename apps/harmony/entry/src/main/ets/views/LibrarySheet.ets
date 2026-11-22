/*
 * 资料库 sheet 内容（原型 libSheet，对照 Android LibrarySheet / iOS LibraryDestination）：
 * 2×2 统计入口（节点、订阅、规则、场景）+ 下方列表（设置）。由 Index 用 bindSheet 呈现。
 * 计数在 sheet 出现时读一次，订阅列表变化（导入 / 更新 / 删除）时重读（Android L-P2-2）。
 * 下方列表：受信任 Wi‑Fi（值 = 第一个网络或“无”）、本地代理端口（开 / 关）、设置（同 Android）。
 * 「小组件与控制中心」在鸿蒙只保留服务卡片说明（契约 §17.c：没有三方控制中心磁贴）：点开弹出添加步骤。
 */
import { AppServices } from '../app/AppServices';
import { LibraryDest } from '../app/AppNav';
import { Format } from '../common/Format';
import { ZNavRow } from '../components/ZNavRow';
import { Scene, Settings, Subscription } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

/** 资料库磁贴组件 id（界面测试用）。 */
export function libraryTileId(d: LibraryDest): string {
  return 'zephyr.library.' + d;
}

@ComponentV2
export struct LibrarySheet {
  @Event onOpen: (d: LibraryDest) => void = (d: LibraryDest) => {};
  @Local nodes: number = -1;
  @Local subs: number = -1;
  @Local rules: number = -1;
  @Local scenes: number = -1;
  @Local firstWifi: string = '';
  @Local proxyOn: boolean = false;
  private streams: StreamSub[] = [];

  aboutToAppear(): void {
    const e = AppServices.get().engine;
    this.streams.push(e.subscriptions().subscribe((l: Subscription[]) => {
      this.reload();
    }));
    this.streams.push(e.scenes().subscribe((s: Scene[]) => {
      this.scenes = s.length;
    }));
    this.streams.push(e.settings().subscribe((s: Settings) => {
      this.firstWifi = s.trustedWifi.length > 0 ? s.trustedWifi[0] : '';
      this.proxyOn = s.localProxyEnabled;
    }));
  }

  aboutToDisappear(): void {
    for (const s of this.streams) {
      s.cancel();
    }
    this.streams = [];
  }

  private reload(): void {
    const e = AppServices.get().engine;
    e.nodeIndex().then((i) => {
      this.nodes = i.total;
    }).catch(() => {});
    e.subscriptionsSummary().then((s) => {
      this.subs = s.count;
    }).catch(() => {});
    e.ruleStats().then((r) => {
      this.rules = r.total;
    }).catch(() => {});
  }

  private countText(n: number): string {
    return n < 0 ? '–' : Format.grouped(n);
  }

  private showCardSteps(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.hm_card_title'),
      message: $r('app.string.hm_card_steps'),
      autoCancel: true,
      confirm: { value: $r('app.string.hm_card_ok'), action: () => {} }
    });
  }

  @Builder
  tile(value: string, label: ResourceStr, d: LibraryDest) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t1'))
        .maxLines(1)
        .minFontSize(14)
        .maxFontSize(24)
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.screen_t3'))
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 76 })
    .padding(14)
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.End)
    .backgroundColor($r('app.color.screen_s1'))
    .accessibilityGroup(true)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .id(libraryTileId(d))
    .onClick(() => this.onOpen(d))
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.tile(this.countText(this.nodes), ZTerm.nodes, LibraryDest.NODES)
          this.tile(this.countText(this.subs), ZTerm.subscriptions, LibraryDest.SUBSCRIPTIONS)
        }
        .width('100%')
        Row({ space: 10 }) {
          this.tile(this.countText(this.rules), ZTerm.rules, LibraryDest.RULES)
          this.tile(this.countText(this.scenes), ZTerm.scenes, LibraryDest.SCENES)
        }
        .width('100%')

        Column() {
          ZNavRow({
            title: $r('app.string.hm_card_title'),
            onTap: () => this.showCardSteps()
          })
          ZNavRow({
            title: $r('app.string.settings_trusted_wifi'),
            value: this.firstWifi.length > 0 ? this.firstWifi : ZTerm.none,
            onTap: () => this.onOpen(LibraryDest.TRUSTED_WIFI)
          })
          ZNavRow({
            title: ZTerm.localProxyPort,
            value: this.proxyOn ? ZTerm.on : ZTerm.off,
            onTap: () => this.onOpen(LibraryDest.LOCAL_PROXY)
          })
          ZNavRow({ title: ZTerm.settings, divider: false, onTap: () => this.onOpen(LibraryDest.SETTINGS) })
        }
        .width('100%')
        .margin({ top: 10 })
        .borderRadius(18)
        .clip(true)
        .backgroundColor($r('app.color.screen_s1'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
