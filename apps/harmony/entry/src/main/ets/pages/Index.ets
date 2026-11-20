/*
 * 占位首页：证明工程能起、外链导入请求能到达页面。真正的首页 / 节点库 / 规则 / 订阅 / 设置页面后续再做。
 */
import { IMPORT_REQUEST_KEY, ImportRequest } from '../entryability/DeepLink';

@Entry
@Component
struct Index {
  @StorageProp(IMPORT_REQUEST_KEY) importRequest: ImportRequest | undefined = undefined;

  private importSummary(r: ImportRequest): string {
    if (r.payload !== undefined) {
      return r.scheme + ' · ' + r.payload.kind + ' · ' + r.payload.items.length;
    }
    return r.scheme + ' · ' + (r.errorCode ?? 'invalid');
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.EntryAbility_label'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      if (this.importRequest !== undefined) {
        Text(this.importSummary(this.importRequest))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
