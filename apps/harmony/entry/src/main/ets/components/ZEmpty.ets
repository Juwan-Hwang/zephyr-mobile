/*
 * 空状态 / 错误状态：标题 + 说明 + 可选按钮（“导入订阅”“请重试”）。
 */
@ComponentV2
export struct ZEmpty {
  @Param title: ResourceStr = '';
  @Param message: ResourceStr | undefined = undefined;
  @Param action: ResourceStr | undefined = undefined;
  @Event onAction: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t1'))
        .textAlign(TextAlign.Center)
      if (this.message !== undefined) {
        Text(this.message)
          .fontSize(14)
          .fontColor($r('app.color.screen_t3'))
          .textAlign(TextAlign.Center)
      }
      if (this.action !== undefined) {
        Button(this.action)
          .fontSize(15)
          .fontColor($r('app.color.screen_on_primary'))
          .backgroundColor($r('app.color.screen_primary'))
          .margin({ top: 8 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
