/*
 * J-1 首页场景卡迷你漏斗（设计规范 §9.3；同 Android MiniFunnel / iOS MiniFunnel）：
 * 全部 → 已测速 → 可连通 → 低于 200 ms 四段 3 vp 细条，宽度 log10(count + 1) 归一到 120 vp；前三段 t3，最后一段强调色 base，
 * 其下方写 underThreshold（caption、t1、等宽）。数据来自该场景的 sceneFunnel（契约 §19.a）。
 */
import { MINI_FUNNEL_BAR, MINI_FUNNEL_GAP, MINI_FUNNEL_WIDTH, MiniFunnelGeom } from '../app/HomeModel';
import { Format } from '../common/Format';
import { ZTheme } from '../common/Theme';
import { NodeFunnel } from '../engine/Model';

@ComponentV2
export struct ZMiniFunnel {
  @Param @Require funnel: NodeFunnel;
  /** 无障碍朗读（调用方取好「可连通 x，低于 200 毫秒 y」）。 */
  @Param spoken: string = '';
  @Local theme: ZTheme = ZTheme.shared();

  private widths(): number[] {
    return MiniFunnelGeom.widths(this.funnel);
  }

  private lastX(): number {
    const w = this.widths();
    let x = 0;
    for (let i = 0; i < w.length - 1; i++) {
      x += w[i] + MINI_FUNNEL_GAP;
    }
    return x;
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: MINI_FUNNEL_GAP }) {
        ForEach(this.widths(), (w: number, i: number) => {
          Row()
            .width(w)
            .height(MINI_FUNNEL_BAR)
            .borderRadius(MINI_FUNNEL_BAR / 2)
            .backgroundColor(i === 3 ? this.theme.accentColor() : $r('app.color.screen_t3'))
        }, (w: number, i: number) => String(i))
      }
      Text(Format.grouped(this.funnel.underThreshold))
        .fontSize(11)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t1'))
        .maxLines(1)
        .margin({ left: this.lastX() })
    }
    .width(MINI_FUNNEL_WIDTH)
    .alignItems(HorizontalAlign.Start)
    .accessibilityGroup(true)
    .accessibilityText(this.spoken)
  }
}
