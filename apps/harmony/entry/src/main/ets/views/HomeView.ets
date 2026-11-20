/* 占位，后续提交填充。 */
import { ZEmpty } from '../components/ZEmpty';

@ComponentV2
export struct HomeView {
  @Event onOpenNodes: () => void = () => {};
  @Event onOpenLibrary: () => void = () => {};

  build() {
    ZEmpty({ title: $r('app.string.common_home') })
  }
}
