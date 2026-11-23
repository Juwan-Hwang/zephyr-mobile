import { LengthMetrics } from '@kit.ArkUI';
import { ZTheme } from '../common/Theme';
/*
 * 选择行（同 Android ZChoiceRow / 原型 .row .v）：标题 · 当前值 › ，点按弹出下拉菜单，当前项打勾。
 * 取代设置里的分段控件（结果保留、外观、日志级别），与 Android / iOS 一致。
 */
@ComponentV2
export struct ZChoiceRow {
  @Param title: ResourceStr = '';
  @Param options: ResourceStr[] = [];
  @Param selected: number = 0;
  @Param divider: boolean = true;
  @Event onSelect: (i: number) => void = () => {};
  @Local open: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();

  @Builder
  menu() {
    Column() {
      ForEach(this.options, (o: ResourceStr, i: number) => {
        Row({ space: 8 }) {
          Text(o)
            .fontSize(16)
            .fontColor($r('app.color.screen_t1'))
            .layoutWeight(1)
          if (i === this.selected) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([this.theme.accentColor()])
          }
        }
        .width(200)
        .height(48)
        .padding({ left: 16, right: 16 })
        .stateStyles({ pressed: { .backgroundColor($r('app.color.screen_s3')) }, normal: { .backgroundColor(Color.Transparent) } })
        .onClick(() => {
          this.open = false;
          if (i !== this.selected) {
            this.onSelect(i);
          }
        })
      }, (o: ResourceStr, i: number) => String(i))
    }
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.title)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .layoutWeight(1)
        Text(this.selected >= 0 && this.selected < this.options.length ? this.options[this.selected] : '')
          .fontSize(15)
          .fontColor($r('app.color.screen_t3'))
          .maxLines(1)
        Text('›')
          .fontSize(20)
          .fontColor($r('app.color.screen_t3'))
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .accessibilityGroup(true)
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .stateStyles({ pressed: { .backgroundColor($r('app.color.screen_s3')) }, normal: { .backgroundColor(Color.Transparent) } })
      .onClick(() => {
        this.open = true;
      })
      .bindMenu(this.open, this.menu(), {
        placement: Placement.BottomRight,
        onDisappear: () => {
          this.open = false;
        }
      })

      if (this.divider) {
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(16) })
      }
    }
    .width('100%')
  }
}
