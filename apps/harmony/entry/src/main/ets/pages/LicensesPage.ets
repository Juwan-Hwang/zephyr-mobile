/*
 * 开源许可（占位）：只显示总述，完整许可文本（rawfile/THIRD_PARTY_NOTICES 等）待打包流程确定后再接入。
 */
@ComponentV2
export struct LicensesPage {
  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          Text($r('app.string.licenses_section_app'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          Text($r('app.string.licenses_intro'))
            .fontSize(15)
            .fontColor($r('app.color.screen_t1'))
          Text($r('app.string.licenses_section_notices'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          Text($r('app.string.hm_licenses_placeholder'))
            .fontSize(14)
            .fontColor($r('app.color.screen_t2'))
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .align(Alignment.Top)
    }
    .title($r('app.string.settings_licenses'))
    .backgroundColor($r('app.color.screen_bg'))
  }
}
