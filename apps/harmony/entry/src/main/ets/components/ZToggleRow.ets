/*
 * 开关行：标题 + 可选说明 + Switch。状态由父组件持有（@Param isOn 单向下发，@Event onChange 回传），
 * 父组件在引擎写入成功后再更新，写入失败时开关自然回弹。
 * 打开时用当前强调色（ZTheme）。
 */
import { ZTheme } from '../common/Theme';

@ComponentV2
export struct ZToggleRow {
  @Param title: ResourceStr = '';
  @Param subtitle: ResourceStr | undefined = undefined;
  @Param isOn: boolean = false;
  @Param isEnabled: boolean = true;
  /** 最后一行不画分隔线。 */
  @Param divider: boolean = true;
  @Event onChange: (on: boolean) => void = (on: boolean) => {};
  @Local theme: ZTheme = ZTheme.shared();

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(16)
            .fontColor(this.isEnabled ? $r('app.color.screen_t1') : $r('app.color.screen_t3'))
          if (this.subtitle !== undefined) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor(this.theme.accentColor())
          .enabled(this.isEnabled)
          .onChange((on: boolean) => {
            if (on !== this.isOn) {
              this.onChange(on);
            }
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .padding({ left: 16, right: 12, top: 8, bottom: 8 })

      if (this.divider) {
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
      }
    }
    .width('100%')
  }
}
