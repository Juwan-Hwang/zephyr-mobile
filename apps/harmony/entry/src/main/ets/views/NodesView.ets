/*
 * 节点库（U14 / U15；对照 Android ui/nodes NodesScreen / NodeRows / NodeDetailSheet，iOS Nodes/*）：
 * - 页眉：库总数（大号）+ “个”，下一行“来自 N 个订阅 · N 个地区”；
 * - 搜索（80 ms 去抖）→ engine.queryNodes；有查询词时搜索框下显示“命中数 · 耗时”；
 * - 地区 chips：“全部” + nodeIndex 最大的 8 个分区（码 + 紧凑数量），点按立即查询该地区码；
 * - List + LazyForEach（NodeRowSource，按页 engine.nodeRows）：分区头 + 节点行（名称高亮查询词、倍率灰显 · 协议 · 延迟）；
 * - 置顶分区头：首个可见行不是第 0 行时，列表顶部叠一条当前分区头（同 Android PinnedHeader / iOS NodePinnedHeaderView）；
 * - 右侧索引条：AlphabetIndexer（地区码，点按 / 拖动跳到该分区头，气泡“JP 日本 / 12,034”），≥ 2 个分区时显示；
 *   Android 的轨在分区内按比例落点，鸿蒙用系统索引条跳分区头（平台惯例）；
 * - 停滚 400 ms 自动测可见且无读数的节点（≤ 100），仅 Wi‑Fi 测速开着且网络按流量计费时不测；
 * - 底栏：“第一个可见节点序号 / 命中总数” + “已检测 n”；
 * - 点行打开详情 sheet：地区徽标 + 城市、协议、延迟、服务器:端口、订阅、线路（运营商 · 标签）、“测速”（单测，已有读数也重测）。
 */
import { AppServices } from '../app/AppServices';
import {
  NamePart, NamePartKind, NodeListState, NodeNameParts, NodeRowItem, NodeRowKind, NodeRowSource, RegionChip,
  SETTLE_DELAY_MS
} from '../app/NodeListModel';
import { NodeDetail, NodeSummary, RegionSection } from '../engine/Model';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { NetMeter } from '../common/NetMeter';
import { ZTheme } from '../common/Theme';
import { ZTerm } from '../generated/ZTerms';
import { ZEmpty } from '../components/ZEmpty';

const DEBOUNCE_MS: number = 80;
const ROW_HEIGHT: number = 52;
const RAIL_WIDTH: number = 28;
/** 界面测试用组件 id。 */
export const NODES_LIST_ID: string = 'zephyr.nodes.list';
export const NODES_PINNED_ID: string = 'zephyr.nodes.pinned';
export const NODES_RAIL_ID: string = 'zephyr.nodes.rail';
export const NODES_DETAIL_TEST_ID: string = 'zephyr.nodes.detail.test';

export function nodeRowId(id: number): string {
  return 'zephyr.nodes.row.' + id;
}

@ComponentV2
struct LatencyText {
  @Param ms: number | undefined = undefined;
  @Param testing: boolean = false;
  @Param fontPx: number = 13;

  build() {
    if (this.testing) {
      LoadingProgress()
        .width(16)
        .height(16)
        .color($r('app.color.screen_t3'))
    } else if (Format.latencyValue(this.ms) !== undefined) {
      Text(Format.latencyMsText(this.ms))
        .fontSize(this.fontPx)
        .fontFamily('monospace')
        .fontColor(Labels.latencyColor(Format.latencyClass(this.ms)))
    } else if (this.ms !== undefined) {
      Text($r('app.string.hm_latency_timeout'))
        .fontSize(this.fontPx)
        .fontColor($r('app.color.latency_timeout'))
    } else {
      Text('—')
        .fontSize(this.fontPx)
        .fontColor($r('app.color.latency_unknown'))
    }
  }
}

@ComponentV2
struct RegionBadge {
  @Param region: string = '';

  build() {
    Text(this.region)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontFamily('monospace')
      .fontColor($r('app.color.screen_t2'))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(4)
      .backgroundColor($r('app.color.screen_s3'))
  }
}

@ComponentV2
struct NodeRowView {
  @Param item: NodeRowItem | undefined = undefined;
  @Param highlights: string[] = [];
  @Event onTap: () => void = () => {};
  @Local theme: ZTheme = ZTheme.shared();

  private loaded(): boolean {
    return this.item !== undefined && this.item.node !== undefined;
  }

  private parts(): NamePart[] {
    const it = this.item;
    return it !== undefined && it.node !== undefined ? NodeNameParts.split(it.node.name, this.highlights) : [];
  }

  private protocol(): string {
    const it = this.item;
    return it !== undefined && it.node !== undefined ? it.node.protocol : '';
  }

  private partColor(p: NamePart): ResourceColor {
    if (p.kind === NamePartKind.HIT) {
      return this.theme.accentColor();
    }
    return p.kind === NamePartKind.MULT ? $r('app.color.screen_t3') : $r('app.color.screen_t1');
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.loaded()) {
          Text() {
            ForEach(this.parts(), (p: NamePart) => {
              Span(p.text).fontColor(this.partColor(p))
            }, (p: NamePart, i: number) => i + ':' + p.kind + ':' + p.text)
          }
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

          Text(this.protocol())
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor($r('app.color.screen_t3'))
          Row() {
            LatencyText({ ms: this.item?.latencyMs, testing: this.item !== undefined && this.item.testing })
          }
          .width(64)
          .justifyContent(FlexAlign.End)
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
    .id(this.item !== undefined && this.item.node !== undefined ? nodeRowId(this.item.node.id) : '')
    .onClick(() => {
      if (this.loaded()) {
        this.onTap();
      }
    })
  }
}

@ComponentV2
struct SectionHeaderView {
  @Param section: RegionSection | undefined = undefined;

  build() {
    Row({ space: 12 }) {
      RegionBadge({ region: this.section !== undefined ? this.section.region : '' })
      Text(this.section !== undefined ? this.section.name : '')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t1'))
        .layoutWeight(1)
      Text(this.section !== undefined ? Format.grouped(this.section.count) : '')
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
struct RegionChipView {
  @Param label: string = '';
  @Param detail: string = '';
  @Param selected: boolean = false;
  @Event onTap: () => void = () => {};
  @Local theme: ZTheme = ZTheme.shared();

  build() {
    Row({ space: 6 }) {
      Text(this.label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selected ? this.theme.accentColor() : $r('app.color.screen_t1'))
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t3'))
      }
    }
    .height(32)
    .padding({ left: 12, right: 12 })
    .borderRadius(16)
    .backgroundColor(this.selected ? this.theme.accentSoft() : $r('app.color.screen_s3'))
    .onClick(() => this.onTap())
  }
}

@ComponentV2
export struct NodesView {
  @Event onImport: () => void = () => {};
  /** 初始查询（指令面板“查看全部”）。 */
  @Param initialQuery: string = '';

  @Local query: string = '';
  @Local total: number = 0;
  @Local tookMicros: number = 0;
  @Local testedCount: number = 0;
  @Local failed: boolean = false;
  @Local loading: boolean = true;
  @Local ranOnce: boolean = false;
  @Local indexTotal: number = 0;
  @Local regionCount: number = 0;
  @Local subscriptionCount: number = 0;
  @Local chips: RegionChip[] = [];
  @Local highlights: string[] = [];
  @Local sections: RegionSection[] = [];
  @Local pinned: RegionSection | undefined = undefined;
  @Local firstPos: number = 0;
  @Local railIndex: number = 0;
  // 详情 sheet
  @Local showDetail: boolean = false;
  @Local selected: NodeSummary | undefined = undefined;
  @Local detail: NodeDetail | undefined = undefined;
  @Local detailLatency: number | undefined = undefined;
  @Local detailTesting: boolean = false;

  private source: NodeRowSource = NodeRowSource.create(AppServices.get().engine);
  private scroller: Scroller = new Scroller();
  private debounce: number = -1;
  private settle: number = -1;
  private myriad: boolean = false;
  private wan: string = '万';

  aboutToAppear(): void {
    this.myriad = this.str($r('app.string.hm_number_myriad')) === 'true';
    this.wan = this.str($r('app.string.hm_unit_wan'));
    this.source.model.onReset = () => {
      this.source.reload();
      this.scroller.scrollToIndex(0);
      this.sections = this.source.model.sections();
      this.pinned = undefined;
      this.firstPos = 0;
      this.scheduleAutoTest();
    };
    this.source.model.onRowChanged = (row: number) => this.source.changed(row);
    this.source.model.onState = (s: NodeListState) => this.apply(s);
    this.source.model.start();
    this.query = this.initialQuery;
    this.source.model.query(this.initialQuery.trim()).then(() => {
      this.ranOnce = true;
    });
  }

  aboutToDisappear(): void {
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
      this.debounce = -1;
    }
    this.cancelSettle();
    this.source.model.dispose();
  }

  private str(r: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id) : '';
    } catch (e) {
      return '';
    }
  }

  private plural(r: Resource, n: number): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getIntPluralStringValueSync(r.id, n, n) : '';
    } catch (e) {
      return '';
    }
  }

  private apply(s: NodeListState): void {
    this.total = s.total;
    this.tookMicros = s.tookMicros;
    this.testedCount = s.testedCount;
    this.failed = s.failed;
    this.loading = s.loading;
    this.indexTotal = s.indexTotal;
    this.regionCount = s.regionCount;
    this.subscriptionCount = s.subscriptionCount;
    this.chips = s.chips;
    this.highlights = s.highlights;
    const sel = this.selected;
    if (sel !== undefined) {
      const lat = this.source.model.latencyOf(sel.id);
      if (lat !== undefined) {
        this.detailLatency = lat;
      }
      this.detailTesting = this.source.model.isTesting(sel.id);
    }
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

  /** chip：立即查询（取消待发的去抖）。 */
  private queryNow(q: string): void {
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
      this.debounce = -1;
    }
    this.query = q;
    this.source.model.query(q);
  }

  private cancelSettle(): void {
    if (this.settle >= 0) {
      clearTimeout(this.settle);
      this.settle = -1;
    }
  }

  /** 停滚（或新结果）后 SETTLE_DELAY_MS 自动测可见行。 */
  private scheduleAutoTest(): void {
    this.cancelSettle();
    this.settle = setTimeout(() => {
      this.settle = -1;
      this.source.model.autoTest(NetMeter.isMetered());
    }, SETTLE_DELAY_MS);
  }

  private onVisible(start: number, end: number): void {
    this.source.model.setVisible(start, end);
    this.pinned = start > 0 ? this.source.model.sectionAt(start) : undefined;
    this.firstPos = this.source.model.position();
    const sec = this.source.model.sectionAt(start);
    if (sec !== undefined) {
      const i = this.sections.findIndex((s: RegionSection) => s.rowOffset === sec.rowOffset);
      if (i >= 0) {
        this.railIndex = i;
      }
    }
  }

  private openDetail(n: NodeSummary): void {
    this.selected = n;
    this.detail = undefined;
    this.detailLatency = this.source.model.latencyOf(n.id) ?? n.latencyMs;
    this.detailTesting = this.source.model.isTesting(n.id);
    this.showDetail = true;
    const id = n.id;
    AppServices.get().engine.node(id).then((d: NodeDetail) => {
      if (this.selected !== undefined && this.selected.id === id) {
        this.detail = d;
        if (this.detailLatency === undefined) {
          this.detailLatency = d.latencyMs;
        }
      }
    }).catch(() => {});
  }

  private subtitle(): string {
    const parts: string[] = [];
    if (this.subscriptionCount > 0) {
      parts.push(this.plural($r('app.plural.nodes_from_subs'), this.subscriptionCount));
    }
    parts.push(this.plural($r('app.plural.common_region_count'), this.regionCount));
    return parts.join(' · ');
  }

  @Builder
  header() {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Text(Format.grouped(this.indexTotal))
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t1'))
        Text(this.plural($r('app.plural.nodes_total_unit'), this.indexTotal))
          .fontSize(15)
          .fontColor($r('app.color.screen_t3'))
          .margin({ bottom: 8 })
      }
      .alignItems(VerticalAlign.Bottom)
      Text(this.subtitle())
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 22, right: 22 })
  }

  @Builder
  chipRow() {
    Scroll() {
      Row({ space: 8 }) {
        RegionChipView({
          label: this.str(ZTerm.all),
          selected: this.query.trim().length === 0,
          onTap: () => this.queryNow('')
        })
        ForEach(this.chips, (c: RegionChip) => {
          RegionChipView({
            label: c.region,
            detail: Format.chip(c.count, this.myriad, this.wan),
            selected: this.query.trim().toLowerCase() === c.region.toLowerCase(),
            onTap: () => this.queryNow(c.region)
          })
        }, (c: RegionChip) => c.region)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  footer() {
    Row() {
      Text(this.firstPos > 0 ? Format.grouped(this.firstPos) + ' / ' + Format.grouped(this.total) : '')
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t3'))
      Blank()
      Text($r('app.string.nodes_tested', Format.grouped(this.testedCount)))
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t3'))
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.screen_bg'))
    .opacity(0.94)
  }

  @Builder
  list() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ scroller: this.scroller }) {
        LazyForEach(this.source, (item: NodeRowItem) => {
          ListItem() {
            if (item.kind === NodeRowKind.HEADER) {
              SectionHeaderView({ section: item.section })
            } else {
              NodeRowView({
                item: item,
                highlights: this.highlights,
                onTap: () => {
                  if (item.node !== undefined) {
                    this.openDetail(item.node);
                  }
                }
              })
            }
          }
          .height(ROW_HEIGHT)
        }, (item: NodeRowItem) => item.key)
      }
      .id(NODES_LIST_ID)
      .width('100%')
      .height('100%')
      .padding({ right: this.sections.length > 1 ? RAIL_WIDTH + 6 : 0 })
      .contentEndOffset(48)
      .cachedCount(10)
      .scrollBar(BarState.Off)
      .onScrollIndex((start: number, end: number) => this.onVisible(start, end))
      .onScrollStart(() => this.cancelSettle())
      .onScrollStop(() => this.scheduleAutoTest())

      if (this.pinned !== undefined) {
        Row() {
          SectionHeaderView({ section: this.pinned })
        }
        .id(NODES_PINNED_ID)
        .width('100%')
        .padding({ right: this.sections.length > 1 ? RAIL_WIDTH + 6 : 0 })
        .opacity(0.96)
        .shadow({ radius: 4, color: '#14000000', offsetY: 1 })
      }

      if (this.sections.length > 1) {
        Row() {
          AlphabetIndexer({ arrayValue: this.sections.map((s: RegionSection) => s.region), selected: this.railIndex })
            .id(NODES_RAIL_ID)
            .height('100%')
            .itemSize(RAIL_WIDTH - 8)
            .font({ size: 10, weight: FontWeight.Medium, family: 'monospace' })
            .color($r('app.color.color_accent'))
            .selectedColor($r('app.color.screen_on_primary'))
            .selectedBackgroundColor($r('app.color.color_accent'))
            .popupColor($r('app.color.screen_t1'))
            .popupBackground($r('app.color.screen_s1'))
            .usingPopup(true)
            .popupPosition({ x: 48, y: 24 })
            .alignStyle(IndexerAlign.Right)
            .onSelect((i: number) => {
              if (i >= 0 && i < this.sections.length) {
                this.railIndex = i;
                this.scroller.scrollToIndex(this.sections[i].rowOffset);
              }
            })
            .onRequestPopupData((i: number): string[] => {
              if (i < 0 || i >= this.sections.length) {
                return [];
              }
              const s = this.sections[i];
              return [s.name, Format.grouped(s.count)];
            })
        }
        .width(RAIL_WIDTH)
        .height('100%')
        .position({ right: 0, top: 0 })
      }

      Column() {
        Blank()
        this.footer()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  detailRow(label: ResourceStr, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.screen_t1'))
      Blank()
      Text(value)
        .fontSize(14)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t3'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '65%' })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
  }

  private place(n: NodeSummary): string {
    return n.city !== undefined && n.city.length > 0 ? n.city : n.region;
  }

  private route(n: NodeSummary): string {
    const parts: string[] = [];
    if (n.carrier !== undefined && n.carrier.length > 0) {
      parts.push(n.carrier);
    }
    if (n.tag !== undefined && n.tag.length > 0) {
      parts.push(n.tag);
    }
    return parts.join(' · ');
  }

  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      if (this.selected !== undefined) {
        Text(this.selected.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.screen_t1'))
          .padding({ left: 22, right: 22 })
          .width('100%')
        Row({ space: 12 }) {
          RegionBadge({ region: this.selected.region })
          Text(this.place(this.selected))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
        }
        .padding({ left: 22, right: 22 })
        .width('100%')

        Column() {
          this.detailRow($r('app.string.nodes_detail_protocol'),
            this.selected.protocol.length > 0 ? this.selected.protocol : '—')
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          Row() {
            Text($r('app.string.nodes_detail_latency'))
              .fontSize(15)
              .fontColor($r('app.color.screen_t1'))
            Blank()
            LatencyText({ ms: this.detailLatency, testing: this.detailTesting, fontPx: 14 })
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          this.detailRow($r('app.string.nodes_detail_server'),
            this.detail !== undefined ? this.detail.server + ':' + this.detail.port : '—')
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          this.detailRow(ZTerm.subscription,
            this.detail !== undefined && this.detail.subscription.length > 0 ? this.detail.subscription : '—')
          if (this.selected.tag !== undefined) {
            Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
            this.detailRow($r('app.string.nodes_detail_route'), this.route(this.selected))
          }
        }
        .borderRadius(12)
        .backgroundColor($r('app.color.screen_s1'))
        .margin({ left: 16, right: 16 })

        Row() {
          Text(this.detailTesting ? ZTerm.testing : $r('app.string.nodes_detail_test'))
            
            .fontSize(15)
            .fontColor(this.detailTesting ? $r('app.color.screen_t3') : $r('app.color.color_accent'))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .borderRadius(12)
        .backgroundColor($r('app.color.screen_s1'))
        .margin({ left: 16, right: 16 })
        .id(NODES_DETAIL_TEST_ID)
        .onClick(() => {
          const s = this.selected;
          if (s !== undefined && !this.detailTesting) {
            this.detailTesting = true;
            this.source.model.testOne(s.id);
          }
        })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 24 })
  }

  build() {
    // 标题由外层 NavDestination 给（Index 路由 nodes）。
    Column({ space: 10 }) {
      this.header()
      Search({ value: this.query, placeholder: $r('app.string.nodes_search_placeholder') })
        
        .height(40)
        .margin({ left: 16, right: 16, top: 8 })
        .backgroundColor($r('app.color.screen_s3'))
        .fontColor($r('app.color.screen_t1'))
        .onChange((v: string) => this.onQuery(v))
      if (this.query.trim().length > 0 && this.ranOnce && !this.failed) {
        Text($r('app.string.nodes_search_stats', Format.grouped(this.total), Format.micros(this.tookMicros)))
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 22, right: 22 })
      }
      this.chipRow()

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
        ZEmpty({ title: ZTerm.noResults, message: $r('app.string.nodes_no_match', this.query.trim()) })
      } else {
        this.list()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.screen_bg'))
    .bindSheet(this.showDetail, this.detailSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.screen_bg'),
      onDisappear: () => {
        this.showDetail = false;
        this.selected = undefined;
        this.detail = undefined;
      }
    })
  }
}
