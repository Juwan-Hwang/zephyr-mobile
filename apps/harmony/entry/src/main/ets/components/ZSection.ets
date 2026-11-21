/*
 * 分组（设置 / 订阅详情的 inset-grouped 列表）：小标题 + 圆角容器 + 可选脚注。行之间的分隔线由行自己画（ZToggleRow / ZNavRow）。
 */
@ComponentV2
export struct ZSection {
  @Param header: ResourceStr | undefined = undefined;
  @Param footer: ResourceStr | undefined = undefined;
  @BuilderParam content: () => void = ZSectionEmpty;

  build() {
    Column({ space: 6 }) {
      if (this.header !== undefined) {
        Text(this.header)
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 16, right: 16 })
      }
      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius(14)
      .clip(true)
      .backgroundColor($r('app.color.screen_s1'))
      if (this.footer !== undefined) {
        Text(this.footer)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
function ZSectionEmpty() {
}
