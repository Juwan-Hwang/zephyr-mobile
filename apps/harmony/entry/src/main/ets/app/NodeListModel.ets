/*
 * 节点库列表模型（对照 Android NodesViewModel）：10^7–10^8 行虚拟列表，从不持有全量。
 * - 行 = 分区头 + 节点；rowOffset（含头行）二分定位 → (分区, 节点序号)；序号按 PAGE 分页经 engine.nodeRows 取，
 *   LRU 最多 CACHE_PAGES 页。
 * - 查询串行：新查询让旧结果作废（runId）；nodeRows 报 stale_token（§16.b①）时用原查询重查一次并回到顶部。
 * - 延迟：latencyUpdates 合并进本地表；只通知可见范围内受影响的行。
 * NodeRowSource 是给 LazyForEach 的 IDataSource，键里带 token / 节点 id / 延迟，数据一变就重建该行。
 */
import { ErrorCode, LatencyUpdate, NodeId, NodeIndex, NodePage, NodeQueryResult, NodeSummary, RegionSection } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine, ZephyrError } from '../engine/ZephyrEngine';

export const NODE_PAGE: number = 200;
export const NODE_CACHE_PAGES: number = 24;
/** 一次手动测速最多的节点数（与 Android testVisible 相同）。 */
export const MAX_TEST_BATCH: number = 100;

export enum NodeRowKind {
  HEADER = 'header',
  NODE = 'node'
}

export interface NodeRowItem {
  row: number;
  kind: NodeRowKind;
  section: RegionSection;
  /** NODE：跨分区的 0 基序号；HEADER：-1。 */
  ordinal: number;
  /** 页还没到时 undefined（显示骨架）。 */
  node?: NodeSummary;
  latencyMs?: number;
  testing: boolean;
  key: string;
}

export interface NodeListState {
  query: string;
  total: number;
  sections: number;
  highlights: string[];
  tookMicros: number;
  failed: boolean;
  loading: boolean;
  testedCount: number;
}

interface RowPos {
  section: RegionSection;
  sectionIndex: number;
  /** -1 = 分区头。 */
  ordinal: number;
}

export class NodeListModel {
  private engine: ZephyrEngine;
  private result: NodeQueryResult | undefined = undefined;
  /** 每个分区之前的节点数（前缀和）。 */
  private before: number[] = [];
  private pages: Map<number, NodeSummary[]> = new Map<number, NodeSummary[]>();
  private inflight: Set<number> = new Set<number>();
  private latency: Map<NodeId, number> = new Map<NodeId, number>();
  private testing: Set<NodeId> = new Set<NodeId>();
  private runId: number = 0;
  private latencySub: StreamSub | undefined = undefined;
  private visibleFrom: number = 0;
  private visibleTo: number = -1;
  private testedCount: number = 0;
  private failed: boolean = false;
  private loading: boolean = false;
  private currentQuery: string = '';

  /** 行数变化 / 查询换了：整表重载。 */
  onReset: () => void = () => {};
  /** 某行数据变了（页到达、延迟更新）。 */
  onRowChanged: (row: number) => void = (row: number) => {};
  onState: (s: NodeListState) => void = (s: NodeListState) => {};

  constructor(engine: ZephyrEngine) {
    this.engine = engine;
  }

  start(): void {
    if (this.latencySub === undefined) {
      this.latencySub = this.engine.latencyUpdates().subscribe((u: LatencyUpdate[]) => this.onLatency(u));
    }
    this.engine.nodeIndex().then((idx: NodeIndex) => {
      this.testedCount = idx.testedCount;
      this.publish();
    }).catch(() => {});
  }

  dispose(): void {
    if (this.latencySub !== undefined) {
      this.latencySub.cancel();
      this.latencySub = undefined;
    }
    this.runId++;
  }

  state(): NodeListState {
    const r = this.result;
    const s: NodeListState = {
      query: this.currentQuery,
      total: r !== undefined ? r.total : 0,
      sections: r !== undefined ? r.sections.length : 0,
      highlights: r !== undefined ? r.highlights : [],
      tookMicros: r !== undefined ? r.tookMicros : 0,
      failed: this.failed,
      loading: this.loading,
      testedCount: this.testedCount
    };
    return s;
  }

  private publish(): void {
    this.onState(this.state());
  }

  /** 运行查询（调用方负责去抖）。旧查询的结果晚到会被丢弃。 */
  async query(q: string): Promise<void> {
    const id = ++this.runId;
    this.currentQuery = q;
    this.loading = true;
    this.publish();
    try {
      const r = await this.engine.queryNodes(q);
      if (id !== this.runId) {
        return;
      }
      this.result = r;
      const before: number[] = [];
      let acc = 0;
      for (const s of r.sections) {
        before.push(acc);
        acc += s.count;
      }
      this.before = before;
      this.pages.clear();
      this.inflight.clear();
      this.failed = false;
    } catch (e) {
      if (id !== this.runId) {
        return;
      }
      this.failed = true;
    } finally {
      if (id === this.runId) {
        this.loading = false;
      }
    }
    this.onReset();
    this.publish();
  }

  retry(): Promise<void> {
    return this.query(this.currentQuery);
  }

  rowCount(): number {
    const r = this.result;
    if (r === undefined || this.failed) {
      return 0;
    }
    return r.total + r.sections.length;
  }

  private pos(row: number): RowPos | undefined {
    const r = this.result;
    if (r === undefined || r.sections.length === 0 || row < 0 || row >= this.rowCount()) {
      return undefined;
    }
    const secs = r.sections;
    let lo = 0;
    let hi = secs.length - 1;
    while (lo < hi) {
      const m = Math.floor((lo + hi + 1) / 2);
      if (secs[m].rowOffset <= row) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    const s = secs[lo];
    const k = row - s.rowOffset;
    const p: RowPos = { section: s, sectionIndex: lo, ordinal: k === 0 ? -1 : this.before[lo] + k - 1 };
    return p;
  }

  /** 序号 → 行号（页到达时通知用）。 */
  private rowOf(ordinal: number): number {
    const r = this.result;
    if (r === undefined) {
      return -1;
    }
    let lo = 0;
    let hi = this.before.length - 1;
    while (lo < hi) {
      const m = Math.floor((lo + hi + 1) / 2);
      if (this.before[m] <= ordinal) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    return r.sections[lo].rowOffset + 1 + (ordinal - this.before[lo]);
  }

  private nodeAt(ordinal: number): NodeSummary | undefined {
    const page = Math.floor(ordinal / NODE_PAGE);
    const rows = this.pages.get(page);
    if (rows === undefined) {
      return undefined;
    }
    // LRU：命中移到最新。
    this.pages.delete(page);
    this.pages.set(page, rows);
    const i = ordinal - page * NODE_PAGE;
    return i < rows.length ? rows[i] : undefined;
  }

  /** LazyForEach.getData：纯读 + 缺页时发起加载（异步，到达后逐行通知）。 */
  item(row: number): NodeRowItem {
    const p = this.pos(row);
    const token = this.result !== undefined ? this.result.token : 0;
    if (p === undefined) {
      const empty: RegionSection = { region: '', name: '', count: 0, rowOffset: 0 };
      const it: NodeRowItem = { row: row, kind: NodeRowKind.HEADER, section: empty, ordinal: -1, testing: false, key: 'x' + row };
      return it;
    }
    if (p.ordinal < 0) {
      const h: NodeRowItem = {
        row: row, kind: NodeRowKind.HEADER, section: p.section, ordinal: -1, testing: false,
        key: token + ':h:' + row
      };
      return h;
    }
    const node = this.nodeAt(p.ordinal);
    if (node === undefined) {
      this.ensurePage(Math.floor(p.ordinal / NODE_PAGE));
    } else if (p.ordinal % NODE_PAGE >= NODE_PAGE / 2) {
      this.ensurePage(Math.floor(p.ordinal / NODE_PAGE) + 1);
    }
    const lat = node !== undefined ? (this.latency.get(node.id) ?? node.latencyMs) : undefined;
    const testing = node !== undefined && this.testing.has(node.id);
    const n: NodeRowItem = {
      row: row, kind: NodeRowKind.NODE, section: p.section, ordinal: p.ordinal, node: node, latencyMs: lat,
      testing: testing,
      key: token + ':n:' + row + ':' + (node !== undefined ? String(node.id) : '-') + ':' + String(lat) + ':' + (testing ? 't' : '')
    };
    return n;
  }

  private ensurePage(page: number): void {
    const r = this.result;
    if (r === undefined || page * NODE_PAGE >= r.total || this.pages.has(page) || this.inflight.has(page)) {
      return;
    }
    this.inflight.add(page);
    const token = r.token;
    const runId = this.runId;
    this.engine.nodeRows(token, page * NODE_PAGE, NODE_PAGE).then((res: NodePage) => {
      this.inflight.delete(page);
      if (runId !== this.runId) {
        return;
      }
      this.pages.set(page, res.rows);
      while (this.pages.size > NODE_CACHE_PAGES) {
        const oldest = this.pages.keys().next();
        if (oldest.done) {
          break;
        }
        this.pages.delete(oldest.value);
      }
      this.notifyRange(page * NODE_PAGE, page * NODE_PAGE + res.rows.length);
    }).catch((e: Object) => {
      this.inflight.delete(page);
      if (runId !== this.runId) {
        return;
      }
      const err = ZephyrError.from(e);
      if (err.code === ErrorCode.STALE_TOKEN) {
        // §16.b①：句柄被淘汰，静默用原查询重查，列表回到顶部。
        this.query(this.currentQuery);
      } else {
        this.failed = true;
        this.onReset();
        this.publish();
      }
    });
  }

  /** 通知 [ordFrom, ordTo) 中落在可见范围（±1 屏）里的行。 */
  private notifyRange(ordFrom: number, ordTo: number): void {
    if (this.visibleTo < this.visibleFrom) {
      return;
    }
    const span = this.visibleTo - this.visibleFrom + 1;
    const lo = Math.max(0, this.visibleFrom - span);
    const hi = Math.min(this.rowCount() - 1, this.visibleTo + span);
    for (let row = lo; row <= hi; row++) {
      const p = this.pos(row);
      if (p !== undefined && p.ordinal >= ordFrom && p.ordinal < ordTo) {
        this.onRowChanged(row);
      }
    }
  }

  /** List.onScrollIndex 回调。 */
  setVisible(from: number, to: number): void {
    this.visibleFrom = from;
    this.visibleTo = to;
  }

  /** 可见范围内已加载的节点 id（测速按钮用）。 */
  visibleIds(): NodeId[] {
    const out: NodeId[] = [];
    for (let row = this.visibleFrom; row <= this.visibleTo && out.length < MAX_TEST_BATCH; row++) {
      const p = this.pos(row);
      if (p !== undefined && p.ordinal >= 0) {
        const n = this.nodeAt(p.ordinal);
        if (n !== undefined) {
          out.push(n.id);
        }
      }
    }
    return out;
  }

  /** 测速：可见节点（手动按钮）或单个节点（点行）。已在测的跳过。 */
  test(ids: NodeId[]): void {
    const todo = ids.filter((id: NodeId) => !this.testing.has(id)).slice(0, MAX_TEST_BATCH);
    if (todo.length === 0) {
      return;
    }
    for (const id of todo) {
      this.testing.add(id);
    }
    this.notifyIds(todo);
    this.engine.testLatency(todo).catch(() => {
      for (const id of todo) {
        this.testing.delete(id);
      }
      this.notifyIds(todo);
    });
  }

  private onLatency(batch: LatencyUpdate[]): void {
    const ids: NodeId[] = [];
    for (const u of batch) {
      this.latency.set(u.id, u.latencyMs);
      this.testing.delete(u.id);
      ids.push(u.id);
    }
    this.testedCount += batch.length;
    this.notifyIds(ids);
    this.publish();
  }

  private notifyIds(ids: NodeId[]): void {
    if (this.visibleTo < this.visibleFrom) {
      return;
    }
    const set = new Set<NodeId>(ids);
    for (let row = this.visibleFrom; row <= this.visibleTo; row++) {
      const p = this.pos(row);
      if (p !== undefined && p.ordinal >= 0) {
        const n = this.nodeAt(p.ordinal);
        if (n !== undefined && set.has(n.id)) {
          this.onRowChanged(row);
        }
      }
    }
  }

  latencyOf(id: NodeId): number | undefined {
    return this.latency.get(id);
  }

  /** 测试辅助：行号 → 序号映射正确性。 */
  ordinalToRow(ordinal: number): number {
    return this.rowOf(ordinal);
  }
}

/** LazyForEach 数据源：委托给 NodeListModel，自己只管监听器。 */
export class NodeRowSource implements IDataSource {
  readonly model: NodeListModel;
  private listeners: DataChangeListener[] = [];

  constructor(model: NodeListModel) {
    this.model = model;
  }

  static create(engine: ZephyrEngine): NodeRowSource {
    return new NodeRowSource(new NodeListModel(engine));
  }

  totalCount(): number {
    return this.model.rowCount();
  }

  getData(index: number): NodeRowItem {
    return this.model.item(index);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  reload(): void {
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  changed(index: number): void {
    for (const l of this.listeners) {
      l.onDataChange(index);
    }
  }
}
