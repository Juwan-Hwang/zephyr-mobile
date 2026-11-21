/*
 * 场景漏斗（原型 .funnel 811–816，审计 U11；对照 Android ui/scene/SceneFunnel.kt、iOS SceneFunnel）：
 * 每步一行“数量 · 条 · 标签”，条宽为对数刻度（SceneSheetModel.barWidth），最后一步用强调色。
 * 条从起始边依次长出（120 ms + 每步 90 ms，600 ms EaseOut，原型 openScene）。读屏每行一个焦点：“标签，N 个节点”。
 * 契约 §15.c 四步：全部 → 已测速 → 可连通 → 延迟低于 {阈值} ms（按服务的步骤需要核心探测，不显示）。
 */
import { FunnelStepValue, SceneSheetModel } from '../app/SceneSheetModel';
import { Format } from '../common/Format';
import { ZTheme } from '../common/Theme';
import { NodeFunnel } from '../engine/Model';
import { ZTerm } from '../generated/ZTerms';

@ComponentV2
export struct SceneFunnel {
  @Param @Require funnel: NodeFunnel;
  @Local grown: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private timer: number = -1;

  aboutToAppear(): void {
    // 下一帧再翻转，隐式动画才有起点。
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.grown = true;
    }, 16);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private label(step: number): ResourceStr {
    switch (step) {
      case 0:
        return ZTerm.all;
      case 1:
        return $r('app.string.scene_funnel_tested');
      case 2:
        return $r('app.string.scene_funnel_reachable');
      default:
        return $r('app.string.scene_funnel_under', this.funnel.thresholdMs);
    }
  }

  private a11y(s: FunnelStepValue): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return Format.grouped(s.count);
      }
      const rm = ctx.resourceManager;
      const l = this.label(s.step);
      const label = typeof l === 'string' ? l : (s.step === 3 ?
        rm.getStringSync((l as Resource).id, this.funnel.thresholdMs) : rm.getStringSync((l as Resource).id));
      const n = Math.min(s.count, 2147483647);
      return label + ', ' + rm.getIntPluralStringValueSync($r('app.plural.common_node_count').id, n, Format.grouped(s.count));
    } catch (e) {
      return Format.grouped(s.count);
    }
  }

  build() {
    Column() {
      ForEach(SceneSheetModel.funnelSteps(this.funnel), (s: FunnelStepValue, i: number) => {
        Row({ space: 12 }) {
          Text(Format.grouped(s.count))
            .width(52)
            .textAlign(TextAlign.End)
            .fontSize(12)
            .fontFamily('monospace')
            .maxLines(1)
            .fontColor(s.step === 3 ? $r('app.color.screen_t1') : $r('app.color.screen_t2'))
          Row()
            .width(SceneSheetModel.barWidth(s.count, SceneSheetModel.funnelTop(SceneSheetModel.funnelSteps(this.funnel))))
            .height(6)
            .borderRadius(3)
            .backgroundColor(s.step === 3 ? this.theme.accentColor() : $r('app.color.screen_s4'))
            .scale({ x: this.grown ? 1 : 0, y: 1, centerX: 0 })
            .animation({ duration: 600, delay: 120 + i * 90, curve: Curve.EaseOut })
          Text(this.label(s.step))
            .layoutWeight(1)
            .fontSize(13)
            .maxLines(2)
            .fontColor(s.step === 3 ? $r('app.color.screen_t2') : $r('app.color.screen_t3'))
        }
        .width('100%')
        .constraintSize({ minHeight: 30 })
        .accessibilityGroup(true)
        .accessibilityText(this.a11y(s))
      }, (s: FunnelStepValue) => String(s.step) + ':' + String(s.count))
    }
    .width('100%')
    .padding({ left: 22, right: 22 })
  }
}
