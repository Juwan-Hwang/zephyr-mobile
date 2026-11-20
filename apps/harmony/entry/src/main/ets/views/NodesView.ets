/* 占位，后续提交填充。 */
import { ZEmpty } from '../components/ZEmpty';

@ComponentV2
export struct NodesView {
  @Event onImport: () => void = () => {};

  build() {
    ZEmpty({ title: $r('app.string.common_nodes') })
  }
}
