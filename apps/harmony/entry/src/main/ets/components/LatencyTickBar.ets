/*
 * 延迟刻度条（设计规范 §9.6，J-6；同 iOS LatencyTickBar）：场景 sheet 候选列表顶部。
 *   200 ms
 *   ┊ ╷╷ ╷ ╷┃╷  ╷   ╷              超时 2
 * 短刻 1×6（t3；≥ 200 ms 琥珀），200 ms 长刻 1×12（t2）并在上方写“200 ms”，当前出口 1×10 强调色；
 * 超时计入右侧“超时 n”（red-text，0 不显示）。数轴总是从左到右；读屏读一句汇总。
 */
import { Format } from '../common/Format';
import { LatencyTicks, Tick, TickSummary } from '../app/LatencyTicks';
import { ZTheme } from '../common/Theme';
import { NodeId, NodeSummary } from '../engine/Model';
import { ZLatency } from '../generated/ZTokens';

const SHORT: number = 6;
const TALL: number = 10;
const LONG: number = 12;

@ComponentV2
export struct LatencyTickBar {
  @Param candidates: NodeSummary[] = [];
  @Param selectedId: NodeId | undefined = undefined;
  @Local barWidth: number = 0;
  @Local theme: ZTheme = ZTheme.shared();

  private summary(): TickSummary {
    return LatencyTicks.summarize(this.candidates, this.selectedId);
  }

  private a11y(): string {
    const s = this.summary();
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync($r('app.string.scene_tickbar_a11y').id, Format.grouped(s.total),
        Format.grouped(s.underThreshold), Format.grouped(s.timeouts)) : '';
    } catch (e) {
      return '';
    }
  }

  build() {
    Row({ space: 16 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (this.barWidth > 0) {
          Text(`${ZLatency.slow} ms`)
            .fontSize(11)
            .fontColor($r('app.color.screen_t3'))
            .position({ x: LatencyTicks.x(ZLatency.slow, this.barWidth) - 18, y: 0 })
            .width(36)
            .textAlign(TextAlign.Center)
          Row()
            .width(1)
            .height(LONG)
            .backgroundColor($r('app.color.screen_t2'))
            .position({ x: LatencyTicks.x(ZLatency.slow, this.barWidth) - 0.5, y: 30 - LONG })
          ForEach(this.summary().ticks, (t: Tick) => {
            Row()
              .width(1)
              .height(t.selected ? TALL : SHORT)
              .backgroundColor(t.selected ? this.theme.accentColor()
                : (t.slow ? $r('app.color.screen_amber') : $r('app.color.screen_t3')))
              .position({ x: LatencyTicks.x(t.ms, this.barWidth) - 0.5, y: 30 - (t.selected ? TALL : SHORT) })
          }, (t: Tick) => String(t.id) + ':' + t.ms + ':' + t.selected)
        }
      }
      .layoutWeight(1)
      .height(30)
      .onAreaChange((o: Area, n: Area) => {
        this.barWidth = Number(n.width);
      })
      if (this.summary().timeouts > 0) {
        Text($r('app.string.scene_tickbar_timeouts', Format.grouped(this.summary().timeouts)))
          .fontSize(11)
          .fontColor($r('app.color.screen_red_text'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .direction(Direction.Ltr)
    .accessibilityGroup(true)
    .accessibilityText(this.a11y())
  }
}
