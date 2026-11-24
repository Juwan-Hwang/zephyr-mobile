/*
 * 弹层顶栏（同 Android ZSheet 顶部 / 原型 .sh-top）：左侧 17 号 Medium 标题（可空），右侧“完成”（body、t2，48 触控区）。
 * 取代 bindSheet 的系统标题 + 圆形关闭钮；弹层底色用 screen_s1（Android surface1），拖动条仍由系统画。
 */
@ComponentV2
export struct ZSheetHeader {
  @Param title: ResourceStr = '';
  @Param trailing: ResourceStr = $r('app.string.common_done');
  @Event onDone: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t1'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .accessibilityLevel(typeof this.title === 'string' && this.title.length === 0 ? 'no' : 'auto')
      Text(this.trailing)
        .fontSize(16)
        .fontColor($r('app.color.screen_t2'))
        .constraintSize({ minWidth: 48, minHeight: 48 })
        .padding(12)
        .textAlign(TextAlign.Center)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .stateStyles({ pressed: { .opacity(0.5) }, normal: { .opacity(1) } })
        .onClick(() => this.onDone())
    }
    .width('100%')
    .padding({ left: 22, right: 10, top: 4, bottom: 8 })
  }
}
