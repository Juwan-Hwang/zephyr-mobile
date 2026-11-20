/*
 * 卡片容器（原型 .card）：screen_s1 底、16 圆角、默认 16 内边距。内容由尾随闭包给出：
 *   ZCard() { Text(...) }
 */
@ComponentV2
export struct ZCard {
  @Param pad: number = 16;
  /** 可点卡片（首页“当前节点”跳节点库等）。 */
  @Event onTap: () => void = () => {};
  @BuilderParam content: () => void = ZCardEmpty;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.pad)
    .borderRadius(16)
    .backgroundColor($r('app.color.screen_s1'))
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onTap())
  }
}

@Builder
function ZCardEmpty() {
}
