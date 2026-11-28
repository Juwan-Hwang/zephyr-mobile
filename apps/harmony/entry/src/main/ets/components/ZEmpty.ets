/*
 * 空状态 / 错误状态：标题 + 说明 + 可选按钮（“导入订阅”“请重试”）。
 * 对照 Android ZEmptyState：标题 headline（17 SemiBold）t2、说明 footnote 13/18 t3 居中、按钮 Secondary、上距 12，四周 32。
 */
import { ZBtn } from '../common/ZButtonMods';

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
        .fontWeight(600)
        .lineHeight(22)
        .fontColor($r('app.color.screen_t2'))
        .textAlign(TextAlign.Center)
      if (this.message !== undefined) {
        Text(this.message)
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.screen_t3'))
          .textAlign(TextAlign.Center)
      }
      if (this.action !== undefined) {
        Button(this.action)
          .attributeModifier(ZBtn.secondary())
          .margin({ top: 4 })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
  }
}
