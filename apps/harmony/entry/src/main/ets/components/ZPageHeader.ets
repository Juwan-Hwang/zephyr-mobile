/*
 * 二级页页头（原型 .pg，同 Android PageScaffold）：“‹ 资料库”返回链接（强调色）+ 右侧可选操作 + 30 号大标题。
 * 取代 NavDestination 系统标题栏（圆形返回钮 + 小标题），与 Android / iOS 一致。
 */
import { ZTheme } from '../common/Theme';

@ComponentV2
export struct ZPageHeader {
  @Param backLabel: ResourceStr = '';
  @Param title: ResourceStr = '';
  /** 右侧操作的系统符号（如 sys.symbol.plus）；undefined = 无。 */
  @Param trailingSymbol: Resource | undefined = undefined;
  @Param trailingLabel: Resource = $r('app.string.subs_add');
  @Event onBack: () => void = () => {};
  @Event onTrailing: () => void = () => {};
  @Local theme: ZTheme = ZTheme.shared();

  build() {
    Column() {
      Row() {
        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([this.theme.accentColor()])
          Text(this.backLabel)
            .fontSize(17)
            .fontColor(this.theme.accentColor())
        }
        .height(48)
        .padding({ left: 8, right: 8 })
        .accessibilityGroup(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .stateStyles({ pressed: { .opacity(0.5) }, normal: { .opacity(1) } })
        .onClick(() => this.onBack())
        Blank()
        if (this.trailingSymbol !== undefined) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.trailingSymbol)
              .fontSize(22)
              .fontColor([this.theme.accentColor()])
          }
          .width(48)
          .height(48)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.trailingLabel)
          .onClick(() => this.onTrailing())
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })

      Text(this.title)
        .fontSize(30)
        .fontWeight(600)
        .lineHeight(36)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 22, right: 22 })
        .accessibilityRole(AccessibilityRoleType.TEXT)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 12 })
  }
}
