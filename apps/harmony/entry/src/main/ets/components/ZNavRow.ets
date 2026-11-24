import { LengthMetrics } from '@kit.ArkUI';
/*
 * 导航 / 取值行：标题 · 右侧值 · 箭头。用于设置里的“日志”“开源许可”、订阅详情等。
 */
@ComponentV2
export struct ZNavRow {
  @Param title: ResourceStr = '';
  @Param subtitle: ResourceStr | undefined = undefined;
  @Param value: ResourceStr | undefined = undefined;
  @Param chevron: boolean = true;
  @Param divider: boolean = true;
  @Event onTap: () => void = () => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(16)
            .fontColor($r('app.color.screen_t1'))
          if (this.subtitle !== undefined) {
            Text(this.subtitle)
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.value !== undefined) {
          Text(this.value)
            .fontSize(16)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.chevron) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.screen_t3')])
            .margin({ left: -6 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      if (this.divider) {
        Divider().strokeWidth(1).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(20) })
      }
    }
    .width('100%')
    .accessibilityGroup(true)
    .stateStyles({ pressed: { .backgroundColor($r('app.color.screen_pressed')) }, normal: { .backgroundColor(Color.Transparent) } })
    .onClick(() => this.onTap())
  }
}
