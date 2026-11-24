/*
 * 分组（同 Android ZListGroup + ZSectionHeader）（设置 / 订阅详情的 inset-grouped 列表）：小标题 + 圆角容器 + 可选脚注。行之间的分隔线由行自己画（ZToggleRow / ZNavRow）。
 */
@ComponentV2
export struct ZSection {
  @Param header: ResourceStr | undefined = undefined;
  @Param footer: ResourceStr | undefined = undefined;
  @BuilderParam content: () => void = ZSectionEmpty;

  build() {
    Column({ space: 6 }) {
      if (this.header !== undefined) {
        // Android ZSectionHeader：sectionLabel 13 Medium、t2、距屏边 22。
        Text(this.header)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t2'))
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      }
      Column() {
        this.content()
      }
      .width('100%')
      // Android ZListGroup：card 形 24 圆角、surface2、1 vp hairline 描边。
      .borderRadius(24)
      .clip(true)
      .backgroundColor($r('app.color.screen_s2'))
      .border({ width: 1, color: $r('app.color.screen_hl') })
      if (this.footer !== undefined) {
        Text(this.footer)
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 6, right: 6, top: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
function ZSectionEmpty() {
}
