/*
 * 资料库 tab：订阅 / 规则两段（Android 资料库里还有小组件说明，鸿蒙暂无对应，未移植）。
 * 外链导入请求到达时 Index 会切到本 tab；订阅段始终处理请求，所以有请求时自动回到订阅段。
 */
import { ImportInbox } from '../app/ImportInbox';
import { ZSegmented } from '../components/ZSegmented';
import { ImportRequest } from '../entryability/DeepLink';
import { Subscription as StreamSub } from '../engine/Stream';
import { RulesView } from './RulesView';
import { SubscriptionsView } from './SubscriptionsView';
import { ZTerm } from '../generated/ZTerms';

@ComponentV2
export struct LibraryView {
  @Local segment: number = 0;
  private inboxSub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    this.inboxSub = ImportInbox.stream().subscribe((r: ImportRequest | undefined) => {
      if (r !== undefined) {
        this.segment = 0;
      }
    });
  }

  aboutToDisappear(): void {
    if (this.inboxSub !== undefined) {
      this.inboxSub.cancel();
      this.inboxSub = undefined;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.common_library'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 16, right: 16, top: 24 })
      ZSegmented({
        options: [ZTerm.subscriptions, ZTerm.rules],
        selected: this.segment,
        onSelect: (i: number) => {
          this.segment = i;
        }
      })
        .padding({ left: 16, right: 16 })
      if (this.segment === 0) {
        SubscriptionsView()
          .layoutWeight(1)
      } else {
        RulesView()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
