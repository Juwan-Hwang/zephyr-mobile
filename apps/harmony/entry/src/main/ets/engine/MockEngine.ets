import {
  CommandSuggestion, ConnectionInfo, ConnectionState, ConnectionStatus, ConnectionTrace, defaultSettings, ErrorCode,
  ExitChange, ImportItem, ImportPayload, ImportSource, LATENCY_TIMEOUT, LatencyUpdate, LogLevel, LogLine, NetworkKind,
  NodeDetail, NodeFilterPreview, NodeFunnel, NodeId, NodeIndex, NodePage, NodeQueryResult, NodeSummary, PolicyGroup, ProxyMode, RuleStats,
  RuleTrace, ScanProgress, Scene, SceneException, SceneKind, SceneSource, Settings, StorageInfo, Subscription,
  SubscriptionDiff, SubscriptionsSummary, TraceOverride, TraceTarget, TrafficSample, UsageSummary, copySettings
} from './Model';
import { delay, EventStream, StateStream } from './Stream';
import { ZephyrEngine, ZephyrError } from './ZephyrEngine';
import { ImportPayloadError, ImportPayloads } from './mock/ImportPayloads';
import { MockCatalog } from './mock/MockCatalog';
import {
  javaHash, MockApps, MockCommands, MockConnections, MockGroups, MockLogs, MockScenes, MockSubscriptions, withLatency
} from './mock/MockFixtures';
import { MockRules } from './mock/MockRules';
import { NodeQuery } from './mock/NodeQuery';

export type Clock = () => number;

/** 构造参数（全部可选）。demo = 已连接 2:14:07（截图 / 商店图）；latencyScale 缩放所有模拟耗时（测试用 0）。 */
export interface MockEngineOptions {
  demo?: boolean;
  latencyScale?: number;
  clock?: Clock;
}

const HOUR_MS: number = 3600000;
const DAY_MS: number = 86400000;

/** 契约 §16.g①：Mock 固定凭据（`zephyr:` 后 24 位）。 */
export const MOCK_CREDENTIAL: string = 'zephyr:mockmockmockmockmockmock';
const CREDENTIAL_ALPHABET: string = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const DEMO_UPTIME_MS: number = (2 * 3600 + 14 * 60 + 7) * 1000;
const CONNECT_DELAY_MS: number = 600;
const DISCONNECT_DELAY_MS: number = 250;
const TODAY_BYTES: number = 1800000000;
const BASE_TESTED: number = 41280;
const FUNNEL_SOURCES: number = 2;
const FUNNEL_POOL: number = 512;
const MAX_QUERIES: number = 16;

/** §15.h 4K 名字判定：仅 ASCII 不区分大小写（全角 ４Ｋ、U+212A 不算）。样本 contract/fixtures/uhd-names-v1.json。 */
const UHD: RegExp = new RegExp('4[Kk]|[Uu][Hh][Dd]|8[Kk]');

export function isUhdName(name: string): boolean {
  return UHD.test(name);
}

function copyConnection(c: ConnectionState): ConnectionState {
  const n: ConnectionState = {
    status: c.status, mode: c.mode, since: c.since, globalNodeId: c.globalNodeId, network: c.network, error: c.error
  };
  return n;
}

function copyScene(s: Scene): Scene {
  const n: Scene = {
    id: s.id, kind: s.kind, name: s.name, available: s.available, selected: s.selected, exitIp: s.exitIp,
    source: s.source, testedAt: s.testedAt, note: s.note, exceptions: s.exceptions.slice(), services: s.services.slice(),
    nodeFilter: s.nodeFilter
  };
  return n;
}

function copySubscription(s: Subscription): Subscription {
  const n: Subscription = {
    id: s.id, name: s.name, url: s.url, nodeCount: s.nodeCount, usedBytes: s.usedBytes, totalBytes: s.totalBytes,
    remainingBytes: s.remainingBytes, expiresAt: s.expiresAt, updatedAt: s.updatedAt, autoUpdateHours: s.autoUpdateHours,
    lastDiff: s.lastDiff
  };
  return n;
}

function copyGroup(g: PolicyGroup): PolicyGroup {
  const n: PolicyGroup = { name: g.name, type: g.type, selected: g.selected, memberCount: g.memberCount, testedAt: g.testedAt };
  return n;
}

function exitChange(sceneId: string | undefined, from: NodeSummary, fromIp: string | undefined, to: NodeSummary,
  toIp: string | undefined, affected: string[], unchanged: string[]): ExitChange {
  const c: ExitChange = {
    sceneId: sceneId, fromRegion: from.region, fromIp: fromIp, toRegion: to.region, toIp: toIp,
    affectedApps: affected, unchangedApps: unchanged
  };
  return c;
}

/** 有延迟的排前面（超时 / 未测按 +∞），稳定排序。 */
function byLatency(a: NodeSummary, b: NodeSummary): number {
  const x = a.latencyMs !== undefined && a.latencyMs >= 0 ? a.latencyMs : Number.MAX_SAFE_INTEGER;
  const y = b.latencyMs !== undefined && b.latencyMs >= 0 ? b.latencyMs : Number.MAX_SAFE_INTEGER;
  return x - y;
}

/**
 * 纯 ArkTS 的确定性引擎（契约 v0 + 原型数据），逐方法对照 Android `MockEngine.kt`。
 * 用于预览、截图、以及 core-ohos 接通前的整机运行。全部在主线程事件循环里跑：查询是 O(|S|) 索引运算，不扫表。
 */
export class MockEngine implements ZephyrEngine {
  readonly kind: string = 'mock';

  private clock: Clock;
  private latencyScale: number;

  private connection: StateStream<ConnectionState>;
  private sceneState: StateStream<Scene[]>;
  private subscriptionState: StateStream<Subscription[]>;
  private settingsState: StateStream<Settings>;
  private groupState: StateStream<PolicyGroup[]>;
  private scan: StateStream<ScanProgress | undefined> = new StateStream<ScanProgress | undefined>(undefined);
  private latencyBus: EventStream<LatencyUpdate[]> = new EventStream<LatencyUpdate[]>();
  private trafficBus: EventStream<TrafficSample> = new EventStream<TrafficSample>();
  private logBus: EventStream<LogLine> = new EventStream<LogLine>();

  private tested: Map<number, number> = new Map<number, number>();
  private testedCount: number = BASE_TESTED;
  private queries: Map<number, NodeQuery> = new Map<number, NodeQuery>();
  private nextToken: number = 1;
  private overrides: Map<string, TraceOverride> = new Map<string, TraceOverride>();
  private proxyCredential: string = MOCK_CREDENTIAL;
  private logLevel: LogLevel = LogLevel.INFO;

  private trafficTimer: number = -1;
  private logTimer: number = -1;
  private logSeq: number = 0;

  constructor(options?: MockEngineOptions) {
    const demo = options !== undefined && options.demo === true;
    const clock = options !== undefined ? options.clock : undefined;
    this.clock = clock ?? ((): number => Date.now());
    this.latencyScale = options !== undefined && options.latencyScale !== undefined ? options.latencyScale : 1;
    const now = this.clock();
    const initial: ConnectionState = {
      status: demo ? ConnectionStatus.CONNECTED : ConnectionStatus.DISCONNECTED,
      mode: ProxyMode.RULE,
      since: demo ? now - DEMO_UPTIME_MS : undefined,
      network: { kind: NetworkKind.WIFI, name: '家', trusted: false }
    };
    this.connection = new StateStream<ConnectionState>(initial);
    this.sceneState = new StateStream<Scene[]>(MockScenes.initial(now));
    this.subscriptionState = new StateStream<Subscription[]>(MockSubscriptions.initial(now));
    // 演示保留原型的受信任网络“家”；真实首次安装为空（§16.c，Android audit #208 U7）。
    const settings = defaultSettings();
    if (demo) {
      settings.trustedWifi = ['家'];
      settings.disconnectOnTrusted = true;
    }
    this.settingsState = new StateStream<Settings>(settings);
    this.groupState = new StateStream<PolicyGroup[]>(MockGroups.initial(now));

    // 流量：有订阅者才起 1 Hz 定时器；未连接时不推样本。
    this.trafficBus.onActive = () => {
      this.trafficTimer = setInterval(() => {
        if (this.connection.value.status === ConnectionStatus.CONNECTED) {
          this.trafficBus.emit(this.sampleAt(this.clock()));
        }
      }, 1000);
    };
    this.trafficBus.onIdle = () => {
      clearInterval(this.trafficTimer);
      this.trafficTimer = -1;
    };
    // 日志：有订阅者才产出，间隔 700–1600 ms（确定性）。
    this.logBus.onActive = () => {
      this.scheduleLog();
    };
    this.logBus.onIdle = () => {
      clearTimeout(this.logTimer);
      this.logTimer = -1;
    };
  }

  private scaled(ms: number): number {
    return Math.floor(ms * this.latencyScale);
  }

  // ── 1. 连接 ──────────────────────────────────────────────────────────────
  connectionState(): StateStream<ConnectionState> {
    return this.connection;
  }

  private patchConnection(f: (c: ConnectionState) => void): void {
    const c = copyConnection(this.connection.value);
    f(c);
    this.connection.value = c;
  }

  async connect(): Promise<void> {
    if (this.connection.value.status === ConnectionStatus.CONNECTED) {
      return;
    }
    if (this.subscriptionState.value.length === 0) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND, 'no subscriptions');
    }
    this.patchConnection((c: ConnectionState) => {
      c.status = ConnectionStatus.CONNECTING;
      c.error = undefined;
    });
    await delay(this.scaled(CONNECT_DELAY_MS));
    this.patchConnection((c: ConnectionState) => {
      c.status = ConnectionStatus.CONNECTED;
      c.since = this.clock();
    });
  }

  async disconnect(): Promise<void> {
    if (this.connection.value.status === ConnectionStatus.DISCONNECTED) {
      return;
    }
    this.patchConnection((c: ConnectionState) => {
      c.status = ConnectionStatus.DISCONNECTING;
    });
    await delay(this.scaled(DISCONNECT_DELAY_MS));
    this.patchConnection((c: ConnectionState) => {
      c.status = ConnectionStatus.DISCONNECTED;
      c.since = undefined;
    });
  }

  reportConnectFailure(error: ZephyrError): void {
    this.patchConnection((c: ConnectionState) => {
      c.status = ConnectionStatus.FAILED;
      c.since = undefined;
      c.error = error.toInfo();
    });
  }

  async setMode(mode: ProxyMode): Promise<void> {
    this.patchConnection((c: ConnectionState) => {
      c.mode = mode;
      if (mode === ProxyMode.GLOBAL && c.globalNodeId === undefined) {
        c.globalNodeId = MockScenes.TOKYO_03.id;
      }
    });
  }

  private currentGlobal(): NodeSummary {
    const id = this.connection.value.globalNodeId ?? MockScenes.TOKYO_03.id;
    return MockScenes.byId(id) ?? MockScenes.TOKYO_03;
  }

  private anyNode(id: NodeId): NodeSummary {
    return MockScenes.byId(id) ?? this.catalogSummary(id);
  }

  async previewGlobalChange(nodeId: NodeId): Promise<ExitChange> {
    const from = this.currentGlobal();
    const to = this.anyNode(nodeId);
    return exitChange(undefined, from, MockScenes.exitIp(from.id), to, MockScenes.exitIp(to.id), [], []);
  }

  async setGlobalNode(id: NodeId): Promise<ExitChange> {
    const from = this.currentGlobal();
    const to = this.anyNode(id);
    this.patchConnection((c: ConnectionState) => {
      c.globalNodeId = id;
    });
    return exitChange(undefined, from, MockScenes.exitIp(from.id), to, MockScenes.exitIp(to.id), [], []);
  }

  // ── 2. 流量 ──────────────────────────────────────────────────────────────
  traffic(): EventStream<TrafficSample> {
    return this.trafficBus;
  }

  async recentTraffic(seconds: number): Promise<TrafficSample[]> {
    const n = Math.max(0, Math.min(300, Math.floor(seconds)));
    const now = this.clock();
    const out: TrafficSample[] = [];
    for (let i = 0; i < n; i++) {
      out.push(this.sampleAt(now - (n - 1 - i) * 1000));
    }
    return out;
  }

  async usageToday(): Promise<UsageSummary> {
    const weights: number[] = [];
    let sum = 0;
    for (let h = 0; h < 24; h++) {
      const w = MockCatalog.hsh(2, h) % 1000 + 200;
      weights.push(w);
      sum += w;
    }
    const hourly = weights.map((w: number) => Math.floor(w * TODAY_BYTES / sum));
    let acc = 0;
    for (const v of hourly) {
      acc += v;
    }
    hourly[23] += TODAY_BYTES - acc;
    const u: UsageSummary = {
      todayBytes: TODAY_BYTES, regionsToday: 4, onlineMillisToday: 6 * HOUR_MS, fastestLatencyMs: 38, hourly: hourly
    };
    return u;
  }

  // ── 3. 场景 ──────────────────────────────────────────────────────────────
  scenes(): StateStream<Scene[]> {
    return this.sceneState;
  }

  private requireScene(id: string): Scene {
    const s = this.sceneState.value.find((x: Scene) => x.id === id);
    if (s === undefined) {
      throw new ZephyrError(ErrorCode.SCENE_NOT_FOUND, id);
    }
    return s;
  }

  private patchScene(id: string, f: (s: Scene) => void): void {
    this.sceneState.value = this.sceneState.value.map((s: Scene) => {
      if (s.id !== id) {
        return s;
      }
      const c = copyScene(s);
      f(c);
      return c;
    });
  }

  private withLatencies(list: NodeSummary[]): NodeSummary[] {
    return list.map((s: NodeSummary) => withLatency(s, this.latencyOf(s.id))).sort(byLatency);
  }

  async sceneCandidates(sceneId: string, region?: string): Promise<NodeSummary[]> {
    const scene = this.requireScene(sceneId);
    return this.withLatencies(MockScenes.pool(region).filter((n: NodeSummary) => scene.nodeFilter === undefined || isUhdName(n.name)));
  }

  async previewSceneChange(sceneId: string, nodeId: NodeId): Promise<ExitChange> {
    const scene = this.requireScene(sceneId);
    const to = MockScenes.byId(nodeId);
    if (to === undefined) {
      throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, `${nodeId}`);
    }
    let affected: string[] = [];
    let unchanged: string[] = [];
    if (scene.kind === SceneKind.AI) {
      affected = ['GPT', 'Gemini'];
      unchanged = scene.exceptions.map((e: SceneException) => e.app);
    } else if (scene.kind === SceneKind.VIDEO) {
      affected = ['Netflix', 'YouTube'];
    }
    return exitChange(sceneId, scene.selected, scene.exitIp, to, MockScenes.exitIp(to.id), affected, unchanged);
  }

  async applySceneChange(sceneId: string, nodeId: NodeId): Promise<void> {
    this.requireScene(sceneId);
    const to = MockScenes.byId(nodeId);
    if (to === undefined) {
      throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, `${nodeId}`);
    }
    this.patchScene(sceneId, (s: Scene) => {
      s.selected = to;
      s.exitIp = MockScenes.exitIp(to.id);
      s.source = SceneSource.MANUAL;
    });
  }

  async retestScene(sceneId: string): Promise<Scene> {
    this.requireScene(sceneId);
    // 模拟真实扫描：512 节点池，每批 64，首页进度条有东西可显示。
    try {
      for (let done = 0; done <= 512; done += 64) {
        const p: ScanProgress = { done: done, total: 512 };
        this.scan.value = p;
        if (done < 512) {
          await delay(this.scaled(110));
        }
      }
    } finally {
      this.scan.value = undefined;
    }
    this.patchScene(sceneId, (s: Scene) => {
      s.testedAt = this.clock();
    });
    return this.requireScene(sceneId);
  }

  scanProgress(): StateStream<ScanProgress | undefined> {
    return this.scan;
  }

  /**
   * §15.c Mock：sourceCount / poolSize 取原型文案（2 / 512）；池 = 按地区轮转的前 512 个节点，
   * 计其 mock 延迟（已测优先，否则缓存）。与 Android / iOS 相同。
   */
  async nodeFunnel(maxAgeMs: number, thresholdMs: number): Promise<NodeFunnel | undefined> {
    const threshold = thresholdMs > 0 ? thresholdMs : 300;
    let t = 0;
    let ok = 0;
    let under = 0;
    const n = MockCatalog.REGIONS.length;
    for (let i = 0; i < FUNNEL_POOL; i++) {
      const r = i % n;
      const j = Math.floor(i / n);
      const ms = this.tested.get(MockCatalog.idOf(r, j)) ?? MockCatalog.cachedLatency(r, j);
      if (ms === undefined) {
        continue;
      }
      t++;
      if (ms >= 0) {
        ok++;
        if (ms < threshold) {
          under++;
        }
      }
    }
    const f: NodeFunnel = {
      sourceCount: FUNNEL_SOURCES, poolSize: FUNNEL_POOL, tested: t, reachable: ok, underThreshold: under, thresholdMs: threshold
    };
    return f;
  }

  async setSceneSource(sceneId: string, source: SceneSource): Promise<NodeSummary | undefined> {
    this.requireScene(sceneId);
    this.patchScene(sceneId, (s: Scene) => {
      s.source = source;
    });
    return undefined;
  }

  async setSceneException(sceneId: string, appId: string, nodeId?: NodeId): Promise<void> {
    this.requireScene(sceneId);
    let node: NodeSummary | undefined = undefined;
    if (nodeId !== undefined) {
      node = MockScenes.byId(nodeId);
      if (node === undefined) {
        throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, `${nodeId}`);
      }
    }
    const picked = node;
    const name = MockApps.nameOf(appId);
    this.patchScene(sceneId, (s: Scene) => {
      const kept = s.exceptions.filter((e: SceneException) => e.appId !== appId);
      if (picked !== undefined) {
        const e: SceneException = { app: name, appId: appId, node: picked };
        kept.push(e);
      }
      s.exceptions = kept;
    });
  }

  /** §15.h Mock（同 Android）：4K 按名字判定；候选 = 当前地区未过滤的 mock 池。 */
  async previewSceneNodeFilter(sceneId: string, filter: string): Promise<NodeFilterPreview> {
    const scene = this.requireScene(sceneId);
    const region = scene.selected.id >= 0 ? scene.selected.region : undefined;
    const all = MockScenes.pool(region).map((n: NodeSummary) => withLatency(n, this.latencyOf(n.id)));
    const keep = all.filter((n: NodeSummary) => isUhdName(n.name));
    const kept = scene.selected.id < 0 || isUhdName(scene.selected.name);
    let suggested: NodeSummary | undefined = undefined;
    if (!kept) {
      for (const n of keep) {
        if (n.latencyMs !== undefined && (suggested === undefined || n.latencyMs < (suggested.latencyMs ?? 0))) {
          suggested = n;
        }
      }
    }
    const p: NodeFilterPreview = {
      matching: keep.length, total: all.length, poolMatching: keep.length, currentKept: kept, suggested: suggested,
      change: suggested !== undefined ? await this.previewSceneChange(sceneId, suggested.id) : undefined
    };
    return p;
  }

  async setSceneNodeFilter(sceneId: string, filter: string | undefined): Promise<void> {
    const scene = this.requireScene(sceneId);
    if (filter !== undefined) {
      const region = scene.selected.id >= 0 ? scene.selected.region : undefined;
      if (!MockScenes.pool(region).some((n: NodeSummary) => isUhdName(n.name))) {
        throw new ZephyrError(ErrorCode.RULE_INPUT_INVALID, 'no 4K node in region'); // = core MobileError.Invalid
      }
    }
    this.patchScene(sceneId, (s: Scene) => {
      s.nodeFilter = filter;
    });
  }

  // ── 4. 策略组 ────────────────────────────────────────────────────────────
  policyGroups(): StateStream<PolicyGroup[]> {
    return this.groupState;
  }

  private requireGroup(name: string): PolicyGroup {
    const g = this.groupState.value.find((x: PolicyGroup) => x.name === name);
    if (g === undefined) {
      throw new ZephyrError(ErrorCode.GROUP_NOT_FOUND, name);
    }
    return g;
  }

  private patchGroup(name: string, f: (g: PolicyGroup) => void): void {
    this.groupState.value = this.groupState.value.map((g: PolicyGroup) => {
      if (g.name !== name) {
        return g;
      }
      const c = copyGroup(g);
      f(c);
      return c;
    });
  }

  async groupMembers(group: string, offset: number, limit: number): Promise<NodePage> {
    const g = this.requireGroup(group);
    const lim = Math.max(0, Math.min(500, limit));
    const end = Math.min(offset + lim, g.memberCount);
    const rows: NodeSummary[] = [];
    for (let k = offset; k < end; k++) {
      const s = MockGroups.member(group, k);
      rows.push(withLatency(s, this.latencyOf(s.id)));
    }
    const page: NodePage = { rows: rows, offset: offset, total: g.memberCount };
    return page;
  }

  async selectInGroup(group: string, nodeId: NodeId): Promise<void> {
    this.requireGroup(group);
    const name = this.anyNode(nodeId).name;
    this.patchGroup(group, (g: PolicyGroup) => {
      g.selected = name;
    });
  }

  async testGroup(group: string): Promise<void> {
    const g = this.requireGroup(group);
    const ids: NodeId[] = [];
    for (let k = 0; k < Math.min(g.memberCount, 100); k++) {
      ids.push(MockGroups.member(group, k).id);
    }
    await this.testLatency(ids);
    this.patchGroup(group, (x: PolicyGroup) => {
      x.testedAt = this.clock();
    });
  }

  // ── 5. 节点库 ────────────────────────────────────────────────────────────
  async nodeIndex(): Promise<NodeIndex> {
    const q = NodeQuery.build('');
    const idx: NodeIndex = { total: q.total, sections: q.sections(), testedCount: this.testedCount };
    return idx;
  }

  async queryNodes(query: string): Promise<NodeQueryResult> {
    const t0 = Date.now();
    const q = NodeQuery.build(query);
    const took = (Date.now() - t0) * 1000;
    const token = this.nextToken++;
    this.queries.set(token, q);
    if (this.queries.size > MAX_QUERIES) {
      const oldest = this.queries.keys().next();
      if (!oldest.done) {
        this.queries.delete(oldest.value);
      }
    }
    const r: NodeQueryResult = {
      query: query, total: q.total, sections: q.sections(), highlights: q.highlights, tookMicros: took, token: token
    };
    return r;
  }

  async nodeRows(token: number, offset: number, limit: number): Promise<NodePage> {
    const q = this.queries.get(token);
    if (q === undefined) {
      // 契约 §5 / §16.b：句柄已淘汰，UI 用原查询重查一次。
      throw new ZephyrError(ErrorCode.STALE_TOKEN, `${token}`);
    }
    // LRU：命中即移到最新。
    this.queries.delete(token);
    this.queries.set(token, q);
    const lim = Math.max(0, Math.min(500, limit));
    const rows: NodeSummary[] = [];
    if (q.groups.length === 0 || offset >= q.total || lim === 0) {
      const empty: NodePage = { rows: rows, offset: offset, total: q.total };
      return empty;
    }
    const end = Math.min(q.total, offset + lim);
    let gi = q.groupForOrdinal(offset);
    let ord = offset;
    while (ord < end) {
      const g = q.groups[gi];
      const groupEnd = g.nodeOffset + g.count;
      while (ord < end && ord < groupEnd) {
        const j = q.indexInRegion(g, ord - g.nodeOffset);
        const id = MockCatalog.idOf(g.region, j);
        rows.push(MockCatalog.summary(g.region, j, this.tested.get(id)));
        ord++;
      }
      gi++;
    }
    const page: NodePage = { rows: rows, offset: offset, total: q.total };
    return page;
  }

  async node(id: NodeId): Promise<NodeDetail> {
    const s = this.anyNode(id);
    const h = MockCatalog.hsh(7, id & 0x7FFFFFFF);
    const latency = this.latencyOf(id);
    const d: NodeDetail = {
      summary: withLatency(s, latency),
      server: `${s.region.toLowerCase()}-${h % 900 + 100}.•••.net`,
      port: 443 + (h % 3) * 1000,
      subscription: MockCatalog.isValid(id) && MockCatalog.indexOf(id) < 8204 ? 'Nebula Cloud' : '其他订阅',
      extra: {},
      latencyMs: latency
    };
    return d;
  }

  async testLatency(ids: NodeId[]): Promise<void> {
    const batch = ids.slice(0, 100);
    if (batch.length === 0) {
      return;
    }
    // 结果按约 50 ms 分桶推送，UI 只重组几次而不是每个节点一次。
    const buckets = new Map<number, NodeId[]>();
    for (const id of batch) {
      const b = Math.floor(this.latencyDelay(id) / 50);
      const list = buckets.get(b);
      if (list === undefined) {
        buckets.set(b, [id]);
      } else {
        list.push(id);
      }
    }
    buckets.forEach((list: NodeId[], bucket: number) => {
      setTimeout(() => {
        const now = this.clock();
        const updates = list.map((id: NodeId) => {
          const ms = this.testedLatencyOf(id);
          if (!this.tested.has(id)) {
            this.testedCount++;
          }
          this.tested.set(id, ms);
          const u: LatencyUpdate = { id: id, latencyMs: ms, at: now };
          return u;
        });
        this.latencyBus.emit(updates);
      }, this.scaled(bucket * 50));
    });
  }

  latencyUpdates(): EventStream<LatencyUpdate[]> {
    return this.latencyBus;
  }

  private latencyDelay(id: NodeId): number {
    const r = Math.floor(id / MockCatalog.ID_STRIDE);
    const j = id % MockCatalog.ID_STRIDE;
    return 80 + MockCatalog.hsh(j, r) % 321; // 80–400 ms
  }

  private testedLatencyOf(id: NodeId): number {
    if (MockCatalog.isValid(id)) {
      return MockCatalog.testedLatency(MockCatalog.regionOf(id), MockCatalog.indexOf(id));
    }
    return MockScenes.latency(id) ?? LATENCY_TIMEOUT;
  }

  private latencyOf(id: NodeId): number | undefined {
    const t = this.tested.get(id);
    if (t !== undefined) {
      return t;
    }
    if (MockCatalog.isValid(id)) {
      return MockCatalog.cachedLatency(MockCatalog.regionOf(id), MockCatalog.indexOf(id));
    }
    return MockScenes.latency(id);
  }

  private catalogSummary(id: NodeId): NodeSummary {
    if (!MockCatalog.isValid(id)) {
      throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, `${id}`);
    }
    return MockCatalog.summary(MockCatalog.regionOf(id), MockCatalog.indexOf(id), this.tested.get(id));
  }

  // ── 6. 规则 ──────────────────────────────────────────────────────────────
  async ruleStats(): Promise<RuleStats> {
    const s: RuleStats = { total: MockRules.total(), layers: MockRules.LAYERS, compiled: true, diskBytes: MockRules.DISK_BYTES };
    return s;
  }

  async testRule(input: string): Promise<RuleTrace> {
    const q = MockRules.normalise(input);
    if (q.length === 0 || new RegExp('\\s').test(q)) {
      throw new ZephyrError(ErrorCode.RULE_INPUT_INVALID, input);
    }
    const hit = MockRules.match(q);
    const took = 10 + q.length;
    const scenes = this.sceneState.value;
    if (hit !== undefined) {
      const sid = MockRules.sceneIdFor(hit.policy);
      const scene = sid !== undefined ? scenes.find((s: Scene) => s.id === sid) : undefined;
      const t: RuleTrace = {
        input: q, isIp: MockRules.isIp(q), layerIndex: hit.layer, rule: hit.rule, ruleNo: hit.ruleNo,
        policy: scene !== undefined ? scene.id : hit.policy, scene: scene,
        exitIp: scene !== undefined ? scene.exitIp : undefined, tookMicros: took
      };
      return t;
    }
    const other = scenes.find((s: Scene) => s.id === 'other');
    const m: RuleTrace = {
      input: q, isIp: MockRules.isIp(q), rule: 'MATCH', policy: 'other', scene: other,
      exitIp: other !== undefined ? other.exitIp : undefined, tookMicros: took
    };
    return m;
  }

  // ── 7. 订阅 ──────────────────────────────────────────────────────────────
  subscriptions(): StateStream<Subscription[]> {
    return this.subscriptionState;
  }

  async subscriptionsSummary(): Promise<SubscriptionsSummary> {
    const list = this.subscriptionState.value;
    let extra = 0;
    for (let i = 2; i < list.length; i++) {
      extra += list[i].nodeCount;
    }
    const s: SubscriptionsSummary = { count: MockSubscriptions.TOTAL_COUNT + list.length - 2, totalNodes: MockCatalog.total() + extra };
    return s;
  }

  /** url / qr / clipboard 走与 core 相同的 §15 规则（契约：Mock 必须拒绝 core 会拒绝的输入）。 */
  async importSubscription(source: ImportSource, payload: string): Promise<Subscription> {
    const p = payload.trim();
    if (p.length === 0) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_INVALID, 'empty');
    }
    if (source === ImportSource.FILE || (source === ImportSource.CLIPBOARD && ImportPayloads.looksLikeConfig(p))) {
      return this.addMock(p, undefined, undefined);
    }
    let items: ImportItem[];
    try {
      items = ImportPayloads.parse(p).items;
    } catch (e) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_INVALID, e instanceof ImportPayloadError ? (e as ImportPayloadError).message : 'invalid');
    }
    let first: Subscription | undefined = undefined;
    for (const it of items) {
      const s = await this.addMock(it.url, it.name, it.autoUpdateHours);
      if (first === undefined) {
        first = s;
      }
    }
    if (first === undefined) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_INVALID, 'no items');
    }
    return first;
  }

  /** §15：同步预解析（多条确认面板、外链 want）。错误转成契约错误：版本过新 / 格式错 = subscription_invalid。 */
  parseImportPayload(payload: string): ImportPayload {
    try {
      return ImportPayloads.parse(payload);
    } catch (e) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_INVALID, e instanceof ImportPayloadError ? (e as ImportPayloadError).message : 'invalid');
    }
  }

  async importItem(source: ImportSource, item: ImportItem): Promise<Subscription> {
    return this.addMock(item.url.trim(), item.name, item.autoUpdateHours);
  }

  private static hostLabel(p: string): string | undefined {
    const m = new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]*)').exec(p);
    if (m === null) {
      return undefined;
    }
    let host = m[1].substring(m[1].lastIndexOf('@') + 1);
    const colon = host.indexOf(':');
    if (colon >= 0) {
      host = host.substring(0, colon);
    }
    if (host.length === 0) {
      return undefined;
    }
    const lastDot = host.lastIndexOf('.');
    const before = lastDot >= 0 ? host.substring(0, lastDot) : host;
    const label = before.substring(before.lastIndexOf('.') + 1);
    return label.length > 0 ? label.charAt(0).toUpperCase() + label.substring(1) : label;
  }

  private async addMock(p: string, name: string | undefined, autoHours: number | undefined): Promise<Subscription> {
    await delay(this.scaled(800));
    const h = MockCatalog.hsh(11, javaHash(p) & 0x7FFFFFFF);
    const id = `sub-${h.toString(16)}`;
    const existing = this.subscriptionState.value.find((s: Subscription) => s.id === id);
    if (existing !== undefined) {
      return existing; // 同一链接：core 也去重
    }
    const now = this.clock();
    const sub: Subscription = {
      id: id, name: name ?? MockEngine.hostLabel(p) ?? '新订阅', url: MockSubscriptions.redact(p),
      nodeCount: 120 + h % 600, totalBytes: 200000000000, usedBytes: 0, remainingBytes: 200000000000,
      expiresAt: now + 30 * DAY_MS, updatedAt: now, autoUpdateHours: autoHours ?? this.settingsState.value.autoUpdateHours
    };
    this.subscriptionState.value = this.subscriptionState.value.concat([sub]);
    return sub;
  }

  async previewUpdate(id: string): Promise<SubscriptionDiff> {
    const s = this.subscriptionState.value.find((x: Subscription) => x.id === id);
    if (s === undefined) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND, id);
    }
    await delay(this.scaled(500));
    return MockSubscriptions.diffFor(s);
  }

  async updateSubscription(id: string): Promise<SubscriptionDiff> {
    const d = await this.previewUpdate(id);
    const now = this.clock();
    this.subscriptionState.value = this.subscriptionState.value.map((s: Subscription) => {
      if (s.id !== id) {
        return s;
      }
      const c = copySubscription(s);
      c.updatedAt = now;
      c.lastDiff = d;
      c.nodeCount = s.nodeCount + d.addedNodes - d.removedNodes;
      return c;
    });
    return d;
  }

  async updateAll(): Promise<SubscriptionDiff[]> {
    const out: SubscriptionDiff[] = [];
    for (const s of this.subscriptionState.value.slice()) {
      out.push(await this.updateSubscription(s.id));
    }
    return out;
  }

  async deleteSubscription(id: string): Promise<void> {
    const list = this.subscriptionState.value;
    if (list.find((s: Subscription) => s.id === id) === undefined) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND, id);
    }
    this.subscriptionState.value = list.filter((s: Subscription) => s.id !== id);
  }

  // ── 8. 连接、日志、设置 ──────────────────────────────────────────────────
  /** 每次调用一条新流：有订阅者时 1 Hz 推送，未连接推空表。 */
  activeConnections(): EventStream<ConnectionInfo[]> {
    const stream = new EventStream<ConnectionInfo[]>();
    let timer = -1;
    let start = 0;
    const tick = () => {
      const t = Math.floor((this.clock() - start) / 1000);
      stream.emit(this.connection.value.status === ConnectionStatus.CONNECTED ? MockConnections.at(start, t) : []);
    };
    stream.onActive = () => {
      start = this.clock();
      tick();
      timer = setInterval(tick, 1000);
    };
    stream.onIdle = () => {
      clearInterval(timer);
      timer = -1;
    };
    return stream;
  }

  async closeConnection(id: string): Promise<void> {
  }

  async closeAll(): Promise<void> {
  }

  recentHosts(limit: number): EventStream<ConnectionInfo[]> {
    const stream = new EventStream<ConnectionInfo[]>();
    const n = Math.max(0, Math.min(limit, 5));
    let timer = -1;
    let start = 0;
    const tick = () => {
      stream.emit(MockConnections.at(start, Math.floor((this.clock() - start) / 1000)).slice(0, n));
    };
    stream.onActive = () => {
      start = this.clock();
      tick();
      timer = setInterval(tick, 1000);
    };
    stream.onIdle = () => {
      clearInterval(timer);
      timer = -1;
    };
    return stream;
  }

  async connectionTrace(host: string): Promise<ConnectionTrace> {
    const t = MockConnections.trace(host, this.clock());
    if (t === undefined) {
      throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, host);
    }
    t.override = this.overrides.get(host);
    return t;
  }

  async overrideHost(host: string, target: TraceTarget, sceneId: string | undefined, persistent: boolean): Promise<void> {
    if (MockConnections.trace(host, this.clock()) === undefined) {
      throw new ZephyrError(ErrorCode.NODE_NOT_FOUND, host);
    }
    if (target === TraceTarget.UNCHANGED) {
      this.overrides.delete(host);
    } else {
      const o: TraceOverride = { target: target, sceneId: sceneId, persistent: persistent };
      this.overrides.set(host, o);
    }
  }

  logs(): EventStream<LogLine> {
    return this.logBus;
  }

  private scheduleLog(): void {
    const wait = this.scaled(700 + MockCatalog.hsh(5, this.logSeq + 1) % 900);
    this.logTimer = setTimeout(() => {
      this.logBus.emit(MockLogs.line(this.logSeq++, this.clock()));
      if (this.logBus.subscriberCount > 0) {
        this.scheduleLog();
      }
    }, Math.max(wait, 1));
  }

  async setLogLevel(level: LogLevel): Promise<void> {
    this.logLevel = level;
  }

  settings(): StateStream<Settings> {
    return this.settingsState;
  }

  async updateSettings(patch: Settings): Promise<void> {
    this.settingsState.value = copySettings(patch);
  }

  async storage(): Promise<StorageInfo> {
    const s: StorageInfo = { nodesBytes: 600000000, rulesBytes: 1900000000, freeBytes: 3100000000 };
    return s;
  }

  async localProxyCredential(): Promise<string> {
    return this.proxyCredential;
  }

  /** §16.g①：同格式新凭据。Mock 用 Math.random 足够；真实引擎由 core 生成。 */
  async resetLocalProxyCredential(): Promise<string> {
    let pw = '';
    for (let i = 0; i < 24; i++) {
      pw += CREDENTIAL_ALPHABET.charAt(Math.floor(Math.random() * CREDENTIAL_ALPHABET.length));
    }
    this.proxyCredential = `zephyr:${pw}`;
    return this.proxyCredential;
  }

  // ── 9. 命令 ──────────────────────────────────────────────────────────────
  async commandSuggestions(input: string): Promise<CommandSuggestion[]> {
    return MockCommands.suggest(input, this.sceneState.value, this.connection.value);
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  /** §6：down 2.4–3.4 MB/s、up 150–260 KB/s，sin + hsh(1, t) 抖动，确定性。 */
  private sampleAt(at: number): TrafficSample {
    const t = Math.floor(at / 1000) | 0;
    const wave = Math.sin(t * 2 * Math.PI / 37.0) * 0.5 + 0.5;
    const jitter = (MockCatalog.hsh(1, t) % 1000) / 1000.0;
    const down = 2400000 + Math.floor((wave * 0.7 + jitter * 0.3) * 1000000);
    const up = 150000 + (MockCatalog.hsh(1, t + 7) % 1000) * 110;
    const s: TrafficSample = { at: at, upBps: up, downBps: down };
    return s;
  }
}
