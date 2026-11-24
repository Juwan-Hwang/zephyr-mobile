/*
 * 卡片容器（原型 .card）：screen_s2 底、24 圆角、1 vp hairline 描边（同 Android ZCard）、默认 16 内边距。内容由尾随闭包给出：
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
    .borderRadius(24)
    .backgroundColor($r('app.color.screen_s2'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onTap())
  }
}

@Builder
function ZCardEmpty() {
}
