/* 占位，后续提交填充。 */
import { ZEmpty } from '../components/ZEmpty';

@ComponentV2
export struct SettingsView {
  @Event onOpenLogs: () => void = () => {};
  @Event onOpenLicenses: () => void = () => {};

  build() {
    ZEmpty({ title: $r('app.string.common_settings') })
  }
}
