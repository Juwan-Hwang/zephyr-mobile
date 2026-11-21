/*
 * 资料库 sheet 内容（原型 libSheet，对照 Android LibrarySheet / iOS LibraryDestination）：
 * 2×2 统计入口（节点、订阅、规则、场景）+ 下方列表（设置）。由 Index 用 bindSheet 呈现。
 * 计数在 sheet 出现时读一次，订阅列表变化（导入 / 更新 / 删除）时重读（Android L-P2-2）。
 * 鸿蒙暂无的行（契约 §17.c）：小组件与控制中心（鸿蒙只有服务卡片，卡片未做）、受信任 Wi‑Fi、本地代理端口——页面做好后再加。
 */
import { AppServices } from '../app/AppServices';
import { LibraryDest } from '../app/AppNav';
import { Format } from '../common/Format';
import { ZNavRow } from '../components/ZNavRow';
import { Scene, Subscription } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

@ComponentV2
export struct LibrarySheet {
  @Event onOpen: (d: LibraryDest) => void = (d: LibraryDest) => {};
  @Local nodes: number = -1;
  @Local subs: number = -1;
  @Local rules: number = -1;
  @Local scenes: number = -1;
  private streams: StreamSub[] = [];

  aboutToAppear(): void {
    const e = AppServices.get().engine;
    this.streams.push(e.subscriptions().subscribe((l: Subscription[]) => {
      this.reload();
    }));
    this.streams.push(e.scenes().subscribe((s: Scene[]) => {
      this.scenes = s.length;
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
