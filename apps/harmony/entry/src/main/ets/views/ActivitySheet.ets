import { LengthMetrics } from '@kit.ArkUI';
/*
 * 最近连接（M1-8 / U11，原型 actSheet；对照 Android ui/activity/ActivitySheet.kt、iOS Activity/ActivitySheet + RecentHostRow）：
 * 首页流量卡（速率区，已连接时）点按打开（bindSheet，同 Android 风区 onActivity / 审计 H-P2-3）。
 * - 契约 §16.e⑧（U28）：engine.recentHosts(50)，按域名聚合、最新在前；sheet 打开期间订阅，关闭即取消。
 * - 行：域名 + “应用 · 场景 · 节点”（没有场景 = 直连）+ 总流量 + ›；点按 → 同一个 sheet 原地变成该域名的连接轨迹
 *   （TraceBody，同 Android H-P2-9：一个遮罩一个 sheet），左上“‹ 最近连接”回到列表。
 * - 长按：关闭该域名的活动连接（iOS H-P2-14 / Android closeHostConnections），吐司“已关闭 n 个连接 / …未能关闭 / 没有活动的连接”。
 * - 空：“连接后，最近访问的域名会显示在这里。”；所有行都不知道应用时加脚注。
 * 纯逻辑 app/RecentHostsModel。
 */
import { ZSheetHeader } from '../components/ZSheetHeader';
import { AppServices } from '../app/AppServices';
import { HapticKind, Haptics } from '../app/Haptics';
import { CloseOutcome, CloseResult, RECENT_HOSTS_MAX, RecentHostsModel } from '../app/RecentHostsModel';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { ConnectionInfo } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { TraceBody } from './TraceBody';

/** 行组件 id 前缀（UiTest）。 */
export function recentHostRowId(host: string): string {
  return 'zephyr.recent.' + host;
}

@ComponentV2
export struct ActivitySheet {
  /** 非空 = 显示该域名的轨迹。 */
  @Event onDone: () => void = () => {};
  @Local traceHost: string = '';
  @Local hosts: ConnectionInfo[] = [];
  @Local loaded: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private sub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    this.sub = AppServices.get().engine.recentHosts(RECENT_HOSTS_MAX).subscribe((l: ConnectionInfo[]) => {
      this.hosts = l;
      this.loaded = true;
    });
  }

  aboutToDisappear(): void {
    if (this.sub !== undefined) {
      this.sub.cancel();
      this.sub = undefined;
    }
  }

  private str(r: Resource, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, ...args) : '';
    } catch (e) {
      return '';
    }
  }

  private plural(r: Resource, n: number): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getIntPluralStringValueSync(r.id, n, n) : '';
    } catch (e) {
      return '';
    }
  }

  private resolve(r: ResourceStr): string {
    return typeof r === 'string' ? r : this.str(r as Resource);
  }

  private subtitle(c: ConnectionInfo): string {
    if (RecentHostsModel.isDirect(c)) {
      return this.str($r('app.string.common_direct'));
    }
    const scene = c.scene !== undefined ? this.resolve(Labels.sceneNameRaw(c.scene)) : '';
    return RecentHostsModel.subtitleParts(c, scene).join(' · ');
  }

  private closeText(r: CloseResult): string {
    switch (r.outcome) {
      case CloseOutcome.NONE:
        return this.str($r('app.string.activity_close_none'));
      case CloseOutcome.CLOSED:
        return this.plural($r('app.plural.activity_closed'), r.count);
      case CloseOutcome.FAILED:
        return this.plural($r('app.plural.activity_close_failed'), r.count);
      default:
        return this.plural($r('app.plural.activity_close_partial'), r.count);
    }
  }

  private closeHost(host: string): void {
    Haptics.play(HapticKind.WARNING);
    const svc = AppServices.get();
    RecentHostsModel.closeHost(svc.engine, host).then((r: CloseResult) => {
      svc.toasts.show(this.closeText(r));
    });
  }

  build() {
    if (this.traceHost.length > 0) {
      this.traceStep()
    } else {
      this.listStep()
    }
  }

  @Builder
  traceStep() {
    Scroll() {
      Column({ space: 12 }) {
        ZSheetHeader({ onDone: () => this.onDone() })
        Text($r('app.string.activity_back'))
          .fontSize(15)
          .fontColor(this.theme.accentColor())
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .accessibilityText($r('app.string.common_back_to', this.str($r('app.string.activity_title'))))
          .onClick(() => {
            this.traceHost = '';
          })
        TraceBody({ host: this.traceHost })
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  listStep() {
    Scroll() {
      Column({ space: 12 }) {
        ZSheetHeader({ title: $r('app.string.activity_title'), onDone: () => this.onDone() })
          .margin({ left: -16, right: -16 })
        if (this.loaded && this.hosts.length === 0) {
          Text($r('app.string.activity_empty'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
            .padding({ left: 22, right: 22, top: 22, bottom: 22 })
        } else if (this.hosts.length > 0) {
          Column() {
            ForEach(this.hosts, (c: ConnectionInfo, i: number) => {
              this.row(c, i > 0)
            }, (c: ConnectionInfo) => c.host)
          }
          .width('100%')
          .borderRadius(24)
          .backgroundColor($r('app.color.screen_s2'))
          .border({ width: 1, color: $r('app.color.screen_hl') })
          .clip(true)

          if (RecentHostsModel.showsNoAppNote(this.hosts)) {
            Text($r('app.string.activity_no_app_note'))
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
              .padding({ left: 6, right: 6 })
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  row(c: ConnectionInfo, divider: boolean) {
    Column() {
      if (divider) {
        Divider().strokeWidth(1).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(20) })
      }
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(c.host)
            .fontSize(16)
            .fontColor($r('app.color.screen_t1'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle(c))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(Format.bytesText(RecentHostsModel.totalBytes(c)))
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t2'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.screen_t3')])
          .accessibilityLevel('no')
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    }
    .width('100%')
    .id(recentHostRowId(c.host))
    .stateStyles({ pressed: { .backgroundColor($r('app.color.screen_pressed')) }, normal: { .backgroundColor(Color.Transparent) } })
    .accessibilityGroup(true)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .accessibilityText($r('app.string.activity_host_a11y', c.host))
    .accessibilityDescription($r('app.string.activity_close_host_a11y', c.host))
    .onClick(() => {
      this.traceHost = c.host;
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => this.closeHost(c.host))
    )
  }
}
