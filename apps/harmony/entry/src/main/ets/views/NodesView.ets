/*
 * 节点库（对照 Android ui/nodes NodesScreen / NodeRows）：搜索（80 ms 去抖）→ engine.queryNodes，
 * List + LazyForEach（NodeRowSource，按页 engine.nodeRows），分区头 + 节点行（名称 · 协议 · 延迟），
 * “测速”按钮测可见节点（≤ 100），点节点行单测该节点。
 * 暂未移植：地区快捷 chip、右侧字母轨、节点详情面板、查询词高亮（见 PR #246 待办）。
 */
import { AppServices } from '../app/AppServices';
import { NodeListState, NodeRowItem, NodeRowKind, NodeRowSource } from '../app/NodeListModel';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZEmpty } from '../components/ZEmpty';
import { ZTerm } from '../generated/ZTerms';

const DEBOUNCE_MS: number = 80;
const ROW_HEIGHT: number = 52;

@ComponentV2
struct NodeRowView {
  @Param item: NodeRowItem | undefined = undefined;
  @Event onTap: () => void = () => {};

  private name(): string {
    const it = this.item;
    return it !== undefined && it.node !== undefined ? it.node.name : '';
  }

  private protocol(): string {
    const it = this.item;
    return it !== undefined && it.node !== undefined ? it.node.protocol : '';
  }

  private loaded(): boolean {
    return this.item !== undefined && this.item.node !== undefined;
  }

  private latencyMs(): number | undefined {
    return this.item !== undefined ? this.item.latencyMs : undefined;
  }

  private isTesting(): boolean {
    return this.item !== undefined && this.item.testing;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.loaded()) {
          Text(this.name())
            .fontSize(15)
            .fontColor($r('app.color.screen_t1'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.protocol())
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor($r('app.color.screen_t3'))
          if (this.isTesting()) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.screen_t3'))
              .margin({ left: 24, right: 24 })
          } else if (Format.latencyValue(this.latencyMs()) !== undefined) {
            Text(Format.latencyMsText(this.latencyMs()))
              .width(64)
              .textAlign(TextAlign.End)
              .fontSize(13)
              .fontFamily('monospace')
              .fontColor(Labels.latencyColor(Format.latencyClass(this.latencyMs())))
          } else if (this.latencyMs() !== undefined) {
            Text($r('app.string.hm_latency_timeout'))
              .width(64)
              .textAlign(TextAlign.End)
              .fontSize(13)
              .fontColor($r('app.color.latency_timeout'))
          } else {
            Text('—')
              .width(64)
              .textAlign(TextAlign.End)
              .fontSize(13)
              .fontColor($r('app.color.latency_unknown'))
          }
        } else {
          // 页未到：骨架条。
          Row()
            .width(180)
            .height(14)
            .borderRadius(4)
            .backgroundColor($r('app.color.screen_s3'))
          Blank()
        }
      }
      .width('100%')
      .height(ROW_HEIGHT - 1)
      .padding({ left: 22, right: 16 })

      Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 22 })
    }
    .width('100%')
    .onClick(() => {
      if (this.loaded()) {
        this.onTap();
      }
    })
  }
}

@ComponentV2
struct SectionHeaderView {
  @Param item: NodeRowItem | undefined = undefined;

  private title(): string {
    return this.item !== undefined ? this.item.section.name : '';
  }

  private region(): string {
    return this.item !== undefined ? this.item.section.region : '';
  }

  private count(): string {
    return this.item !== undefined ? Format.grouped(this.item.section.count) : '';
  }

  build() {
    Row({ space: 12 }) {
      Text(this.region())
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t2'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor($r('app.color.screen_s3'))
      Text(this.title())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t1'))
        .layoutWeight(1)
      Text(this.count())
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t3'))
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: 22, right: 16 })
    .backgroundColor($r('app.color.screen_bg'))
  }
}

@ComponentV2
export struct NodesView {
  @Event onImport: () => void = () => {};

  @Local query: string = '';
  @Local total: number = 0;
  @Local tookMicros: number = 0;
  @Local testedCount: number = 0;
  @Local failed: boolean = false;
  @Local loading: boolean = true;
  @Local ranOnce: boolean = false;

  private source: NodeRowSource = NodeRowSource.create(AppServices.get().engine);
  private scroller: Scroller = new Scroller();
  private debounce: number = -1;

  aboutToAppear(): void {
    this.source.model.onReset = () => {
      this.source.reload();
      this.scroller.scrollToIndex(0);
    };
    this.source.model.onRowChanged = (row: number) => this.source.changed(row);
    this.source.model.onState = (s: NodeListState) => this.apply(s);
    this.source.model.start();
    this.source.model.query('').then(() => {
      this.ranOnce = true;
    });
  }

  aboutToDisappear(): void {
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
      this.debounce = -1;
    }
    this.source.model.dispose();
  }

  private apply(s: NodeListState): void {
    this.total = s.total;
    this.tookMicros = s.tookMicros;
    this.testedCount = s.testedCount;
    this.failed = s.failed;
    this.loading = s.loading;
  }

  private onQuery(q: string): void {
    this.query = q;
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
    }
    this.debounce = setTimeout(() => {
      this.debounce = -1;
      this.source.model.query(q.trim());
    }, DEBOUNCE_MS);
  }

  @Builder
  statsBar() {
    Row({ space: 8 }) {
      Text($r('app.string.nodes_search_stats', Format.grouped(this.total), Format.micros(this.tookMicros)))
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
      Text($r('app.string.nodes_tested', Format.grouped(this.testedCount)))
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
        .layoutWeight(1)
      Button($r('app.string.nodes_detail_test'))
        .type(ButtonType.Capsule)
        .height(28)
        .fontSize(13)
        .fontColor($r('app.color.screen_t1'))
        .backgroundColor($r('app.color.screen_s3'))
        .enabled(this.total > 0)
        .onClick(() => this.source.model.test(this.source.model.visibleIds()))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  build() {
    Column({ space: 10 }) {
      Text(ZTerm.nodes)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 16, right: 16, top: 24 })

      Search({ value: this.query, placeholder: $r('app.string.nodes_search_placeholder') })
        .height(40)
        .margin({ left: 16, right: 16 })
        .backgroundColor($r('app.color.screen_s3'))
        .fontColor($r('app.color.screen_t1'))
        .onChange((v: string) => this.onQuery(v))

      if (this.failed) {
        ZEmpty({
          title: $r('app.string.nodes_error_title'),
          action: $r('app.string.common_try_again'),
          onAction: () => {
            this.source.model.retry();
          }
        })
      } else if (this.ranOnce && !this.loading && this.total === 0 && this.query.trim().length === 0) {
        ZEmpty({
          title: $r('app.string.nodes_empty_title'),
          message: $r('app.string.nodes_empty_message'),
          action: $r('app.string.nodes_empty_action'),
          onAction: () => this.onImport()
        })
      } else if (this.ranOnce && !this.loading && this.total === 0) {
        ZEmpty({ title: $r('app.string.nodes_no_match', this.query.trim()) })
      } else {
        this.statsBar()
        List({ scroller: this.scroller }) {
          LazyForEach(this.source, (item: NodeRowItem) => {
            ListItem() {
              if (item.kind === NodeRowKind.HEADER) {
                SectionHeaderView({ item: item })
              } else {
                NodeRowView({
                  item: item,
                  onTap: () => {
                    if (item.node !== undefined) {
                      this.source.model.test([item.node.id]);
                    }
                  }
                })
              }
            }
            .height(ROW_HEIGHT)
          }, (item: NodeRowItem) => item.key)
        }
        .layoutWeight(1)
        .width('100%')
        .cachedCount(10)
        .scrollBar(BarState.Auto)
        .onScrollIndex((start: number, end: number) => this.source.model.setVisible(start, end))
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
