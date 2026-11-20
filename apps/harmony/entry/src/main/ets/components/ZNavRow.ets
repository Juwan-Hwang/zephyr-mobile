/*
 * 导航 / 取值行：标题 · 右侧值 · 箭头。用于设置里的“日志”“开源许可”、订阅详情等。
 */
@ComponentV2
export struct ZNavRow {
  @Param title: ResourceStr = '';
  @Param value: ResourceStr | undefined = undefined;
  @Param chevron: boolean = true;
  @Param divider: boolean = true;
  @Event onTap: () => void = () => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.title)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .layoutWeight(1)
        if (this.value !== undefined) {
          Text(this.value)
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.chevron) {
          Text('›')
            .fontSize(20)
            .fontColor($r('app.color.screen_t4'))
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })

      if (this.divider) {
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
      }
    }
    .width('100%')
    .onClick(() => this.onTap())
  }
}
