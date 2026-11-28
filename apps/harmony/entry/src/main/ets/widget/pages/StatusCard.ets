/*
 * Zephyr 状态服务卡片（原型 hs，对照 Android ZephyrWidget）：小卡 2×2 = 状态点 + 电源按钮 + 标题 + 模式·出口 + 今日用量；
 * 中卡 2×4 再加场景列（最多 3 行，名称 / 地区+出口 / 上次延迟）。数据来自 ZephyrFormAbility 的快照，没有实时速率。
 * 点电源按钮 = 连接 / 断开（经 EntryAbility 执行，算用户手动操作）；点其余区域打开 App。
 * 卡片页面不能 import 应用代码，键名与 CardSnapshots.binding / CARD_ACTION_PARAM 保持一致。
 */
class CardSceneRow {
  name: string = '';
  exit: string = '';
  ms: string = '';
}

const storage = new LocalStorage();

@Entry(storage)
@Component
struct StatusCard {
  @LocalStorageProp('on') on: boolean = false;
  @LocalStorageProp('busy') busy: boolean = false;
  @LocalStorageProp('title') title: string = 'Zephyr';
  @LocalStorageProp('detail') detail: string = '';
  @LocalStorageProp('today') today: string = '';
  @LocalStorageProp('scenesTitle') scenesTitle: string = '';
  @LocalStorageProp('toggleLabel') toggleLabel: string = '';
  @LocalStorageProp('scenes') scenes: CardSceneRow[] = [];
  @LocalStorageProp('wide') wide: boolean = false;

  private act(kind: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { 'zephyrCard': kind }
    });
  }

  @Builder
  statusColumn() {
    Column() {
      Row() {
        Circle()
          .width(8)
          .height(8)
          .fill(this.on ? $r('app.color.screen_green') : $r('app.color.screen_t3'))
        if (this.wide) {
          Text('Zephyr')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.screen_t2'))
            .margin({ left: 6 })
            .layoutWeight(1)
        } else {
          Blank()
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.power'))
            .fontSize(18)
            .fontColor([this.on ? $r('app.color.screen_on_primary') : $r('app.color.screen_t1')])
        }
        .width(36)
        .height(36)
        .backgroundColor(this.on ? $r('app.color.screen_primary') : $r('app.color.screen_hl'))
        .enabled(!this.busy)
        .accessibilityText(this.toggleLabel)
        .onClick(() => this.act('toggle'))
      }
      .width('100%')

      Blank()
      Text(this.title)
        .fontSize(22)
        .fontColor($r('app.color.screen_t1'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(12)
          .fontColor($r('app.color.screen_t2'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.today.length > 0) {
        Text(this.today)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .maxLines(1)
          .margin({ top: 4 })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  scenesColumn() {
    Column({ space: 8 }) {
      Text(this.scenesTitle)
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
      ForEach(this.scenes, (s: CardSceneRow) => {
        Row({ space: 6 }) {
          Text(s.name)
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
            .width(40)
            .maxLines(1)
          Text(s.exit)
            .fontSize(13)
            .fontColor($r('app.color.screen_t1'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (s.ms.length > 0) {
            Text(s.ms)
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
              .maxLines(1)
          }
        }
        .width('100%')
      }, (s: CardSceneRow, i: number) => i + '|' + s.name + '|' + s.exit + '|' + s.ms)
    }
    .layoutWeight(1)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ left: 16 })
  }

  build() {
    Row() {
      this.statusColumn()
      if (this.wide && this.scenes.length > 0) {
        this.scenesColumn()
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.screen_s1'))
    .onClick(() => this.act('open'))
  }
}
