/*
 * 分段选择（模式 规则 / 全局 / 直连、日志级别等）：options 为显示文案，selected 为下标，选中段 screen_s4 底。
 */
@ComponentV2
export struct ZSegmented {
  @Param options: ResourceStr[] = [];
  @Param selected: number = 0;
  @Param isEnabled: boolean = true;
  @Event onSelect: (index: number) => void = (index: number) => {};

  build() {
    Row() {
      ForEach(this.options, (label: ResourceStr, i: number) => {
        Text(label)
          .fontSize(14)
          .fontWeight(i === this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(i === this.selected ? $r('app.color.screen_t1') : $r('app.color.screen_t2'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor(i === this.selected ? $r('app.color.screen_s4') : Color.Transparent)
          .onClick(() => {
            if (this.isEnabled && i !== this.selected) {
              this.onSelect(i);
            }
          })
      }, (label: ResourceStr, i: number) => String(i))
    }
    .width('100%')
    .padding(2)
    .borderRadius(10)
    .backgroundColor($r('app.color.screen_s3'))
    .opacity(this.isEnabled ? 1 : 0.5)
  }
}
