import {
  CommandSuggestion, ConnectionInfo, ConnectionState, ConnectionStatus, ConnectionTrace, ErrorCode, ExitChange,
  ImportItem, ImportPayload, ImportSource, LatencyUpdate, LogLevel, LogLine, NodeDetail, NodeFilterPreview, NodeFunnel, NodeId, NodeIndex,
  NodePage, NodeQueryResult, NodeSummary, PolicyGroup, ProxyMode, RuleStats, RuleTrace, ScanProgress, Scene,
  SceneFailoverNotice, SceneSource, Settings, StorageInfo, Subscription, SubscriptionDiff, SubscriptionsSummary, TraceTarget,
  TrafficSample, UsageSummary, defaultSettings
} from '../Model';
import { EventStream, StateStream } from '../Stream';
import { ZephyrEngine, ZephyrError } from '../ZephyrEngine';
import { ImportPayloadError, ImportPayloads } from '../mock/ImportPayloads';
import type { MobileCore } from 'libcore_ohos.so';

/**
 * 经 core-ohos NAPI（libcore_ohos.so）的真实引擎。**桩**：core-ohos 目前只导出 version / greeting /
 * MobileCore(subscriptionsSummary, rebuildMockNodes)，所以只有 subscriptionsSummary 真正下沉；其余方法一律
 * 抛 `internal`（message = "not implemented: <方法>"），流返回空的初始值，UI 可以照常订阅。
 * parseImportPayload 是纯解析（§15），直接复用 ArkTS 实现，与 Mock 行为一致。
 *
 * 用 NativeEngine.create(dataDir) 构造：动态 import CoreOhos.ets，.so 缺失时 core 为 undefined，
 * 所有下沉调用抛 `core_crashed`（"libcore_ohos.so not packaged"），而不是在模块加载阶段崩溃。
 *
 * TODO（RustMockEngine）：core-ohos 导出 Rust mock 后，在这里接 rebuildMockNodes / 查询接口，
 * 用同一份 contract/fixtures 对拍。
 */
export class NativeEngine implements ZephyrEngine {
  readonly kind: string = 'native';
  private core: MobileCore | undefined;
  /** create() 时 .so 的加载结果，仅诊断用。 */
  readonly coreVersion: string;

  private connection: StateStream<ConnectionState>;
  private sceneState: StateStream<Scene[]> = new StateStream<Scene[]>([]);
  private scan: StateStream<ScanProgress | undefined> = new StateStream<ScanProgress | undefined>(undefined);
  private groups: StateStream<PolicyGroup[]> = new StateStream<PolicyGroup[]>([]);
  private subs: StateStream<Subscription[]> = new StateStream<Subscription[]>([]);
  private settingsState: StateStream<Settings> = new StateStream<Settings>(defaultSettings());
  private trafficEvents: EventStream<TrafficSample> = new EventStream<TrafficSample>();
  /** M3 接核心探测事件前不发任何通知。 */
  private failoverEvents: EventStream<SceneFailoverNotice> = new EventStream<SceneFailoverNotice>();
  private latencyEvents: EventStream<LatencyUpdate[]> = new EventStream<LatencyUpdate[]>();
  private connEvents: EventStream<ConnectionInfo[]> = new EventStream<ConnectionInfo[]>();
  private hostEvents: EventStream<ConnectionInfo[]> = new EventStream<ConnectionInfo[]>();
  private logEvents: EventStream<LogLine> = new EventStream<LogLine>();

  private constructor(core: MobileCore | undefined, coreVersion: string) {
    this.core = core;
    this.coreVersion = coreVersion;
    const initial: ConnectionState = { status: ConnectionStatus.DISCONNECTED, mode: ProxyMode.RULE };
    this.connection = new StateStream<ConnectionState>(initial);
  }

  /** dataDir：应用沙箱 filesDir 下的目录。.so 缺失或 MobileCore 构造失败时仍返回实例（下沉调用再报错）。 */
  static async create(dataDir: string): Promise<NativeEngine> {
    try {
      const m = await import('./CoreOhos');
      if (!m.coreAvailable()) {
        return new NativeEngine(undefined, '');
      }
      return new NativeEngine(m.openCore(dataDir), m.coreVersion());
    } catch (e) {
      return new NativeEngine(undefined, '');
    }
  }

  get coreLoaded(): boolean {
    return this.core !== undefined;
  }

  private static notImplemented(method: string): ZephyrError {
    return new ZephyrError(ErrorCode.INTERNAL, 'not implemented: ' + method);
  }

  private static ni<T>(method: string): Promise<T> {
    return Promise.reject<T>(NativeEngine.notImplemented(method));
  }

  private requireCore(): MobileCore {
    if (this.core === undefined) {
      throw new ZephyrError(ErrorCode.CORE_CRASHED, 'libcore_ohos.so not packaged');
    }
    return this.core;
  }

  // ── 1. 连接 ──────────────────────────────────────────────────────────────
  connectionState(): StateStream<ConnectionState> {
    return this.connection;
  }

  connect(): Promise<void> {
    return NativeEngine.ni<void>('connect');
  }

  disconnect(): Promise<void> {
    return NativeEngine.ni<void>('disconnect');
  }

  reportConnectFailure(error: ZephyrError): void {
    const c: ConnectionState = {
      status: ConnectionStatus.FAILED,
      mode: this.connection.value.mode,
      error: error.toInfo()
    };
    this.connection.value = c;
  }

  setMode(mode: ProxyMode): Promise<void> {
    return NativeEngine.ni<void>('setMode');
  }

  previewGlobalChange(nodeId: NodeId): Promise<ExitChange> {
    return NativeEngine.ni<ExitChange>('previewGlobalChange');
  }

  setGlobalNode(id: NodeId): Promise<ExitChange> {
    return NativeEngine.ni<ExitChange>('setGlobalNode');
  }

  // ── 2. 流量 ──────────────────────────────────────────────────────────────
  traffic(): EventStream<TrafficSample> {
    return this.trafficEvents;
  }

  recentTraffic(seconds: number): Promise<TrafficSample[]> {
    return NativeEngine.ni<TrafficSample[]>('recentTraffic');
  }

  usageToday(): Promise<UsageSummary> {
    return NativeEngine.ni<UsageSummary>('usageToday');
  }

  // ── 3. 场景 ──────────────────────────────────────────────────────────────
  scenes(): StateStream<Scene[]> {
    return this.sceneState;
  }

  sceneCandidates(sceneId: string, region?: string): Promise<NodeSummary[]> {
    return NativeEngine.ni<NodeSummary[]>('sceneCandidates');
  }

  previewSceneChange(sceneId: string, nodeId: NodeId): Promise<ExitChange> {
    return NativeEngine.ni<ExitChange>('previewSceneChange');
  }

  applySceneChange(sceneId: string, nodeId: NodeId): Promise<void> {
    return NativeEngine.ni<void>('applySceneChange');
  }

  sceneFailovers(): EventStream<SceneFailoverNotice> {
    return this.failoverEvents;
  }

  retestScene(sceneId: string): Promise<Scene> {
    return NativeEngine.ni<Scene>('retestScene');
  }

  scanProgress(): StateStream<ScanProgress | undefined> {
    return this.scan;
  }

  nodeFunnel(maxAgeMs: number, thresholdMs: number): Promise<NodeFunnel | undefined> {
    return NativeEngine.ni<NodeFunnel | undefined>('nodeFunnel');
  }

  setSceneSource(sceneId: string, source: SceneSource): Promise<NodeSummary | undefined> {
    return NativeEngine.ni<NodeSummary | undefined>('setSceneSource');
  }

  setSceneException(sceneId: string, appId: string, nodeId?: NodeId): Promise<void> {
    return NativeEngine.ni<void>('setSceneException');
  }

  previewSceneNodeFilter(sceneId: string, filter: string): Promise<NodeFilterPreview> {
    return NativeEngine.ni<NodeFilterPreview>('previewSceneNodeFilter');
  }

  setSceneNodeFilter(sceneId: string, filter: string | undefined): Promise<void> {
    return NativeEngine.ni<void>('setSceneNodeFilter');
  }

  // ── 4. 策略组 ────────────────────────────────────────────────────────────
  policyGroups(): StateStream<PolicyGroup[]> {
    return this.groups;
  }

  groupMembers(group: string, offset: number, limit: number): Promise<NodePage> {
    return NativeEngine.ni<NodePage>('groupMembers');
  }

  selectInGroup(group: string, nodeId: NodeId): Promise<void> {
    return NativeEngine.ni<void>('selectInGroup');
  }

  testGroup(group: string): Promise<void> {
    return NativeEngine.ni<void>('testGroup');
  }

  // ── 5. 节点库 ────────────────────────────────────────────────────────────
  nodeIndex(): Promise<NodeIndex> {
    return NativeEngine.ni<NodeIndex>('nodeIndex');
  }

  queryNodes(query: string): Promise<NodeQueryResult> {
    return NativeEngine.ni<NodeQueryResult>('queryNodes');
  }

  nodeRows(token: number, offset: number, limit: number): Promise<NodePage> {
    return NativeEngine.ni<NodePage>('nodeRows');
  }

  node(id: NodeId): Promise<NodeDetail> {
    return NativeEngine.ni<NodeDetail>('node');
  }

  testLatency(ids: NodeId[]): Promise<void> {
    return NativeEngine.ni<void>('testLatency');
  }

  latencyUpdates(): EventStream<LatencyUpdate[]> {
    return this.latencyEvents;
  }

  // ── 6. 规则 ──────────────────────────────────────────────────────────────
  ruleStats(): Promise<RuleStats> {
    return NativeEngine.ni<RuleStats>('ruleStats');
  }

  testRule(input: string): Promise<RuleTrace> {
    return NativeEngine.ni<RuleTrace>('testRule');
  }

  // ── 7. 订阅 ──────────────────────────────────────────────────────────────
  subscriptions(): StateStream<Subscription[]> {
    return this.subs;
  }

  /** 唯一真正下沉到 core-ohos 的调用（MobileCore.subscriptionsSummary，同步）。 */
  async subscriptionsSummary(): Promise<SubscriptionsSummary> {
    const core = this.requireCore();
    try {
      const r = core.subscriptionsSummary();
      const s: SubscriptionsSummary = { count: r.count, totalNodes: r.totalNodes };
      return s;
    } catch (e) {
      throw ZephyrError.from(e as Object);
    }
  }

  importSubscription(source: ImportSource, payload: string): Promise<Subscription> {
    return NativeEngine.ni<Subscription>('importSubscription');
  }

  parseImportPayload(payload: string): ImportPayload {
    try {
      return ImportPayloads.parse(payload);
    } catch (e) {
      throw new ZephyrError(ErrorCode.SUBSCRIPTION_INVALID,
        e instanceof ImportPayloadError ? (e as ImportPayloadError).message : 'invalid');
    }
  }

  importItem(source: ImportSource, item: ImportItem): Promise<Subscription> {
    return NativeEngine.ni<Subscription>('importItem');
  }

  previewUpdate(id: string): Promise<SubscriptionDiff> {
    return NativeEngine.ni<SubscriptionDiff>('previewUpdate');
  }

  updateSubscription(id: string): Promise<SubscriptionDiff> {
    return NativeEngine.ni<SubscriptionDiff>('updateSubscription');
  }

  updateAll(): Promise<SubscriptionDiff[]> {
    return NativeEngine.ni<SubscriptionDiff[]>('updateAll');
  }

  deleteSubscription(id: string): Promise<void> {
    return NativeEngine.ni<void>('deleteSubscription');
  }

  // ── 8. 连接、日志、设置 ──────────────────────────────────────────────────
  activeConnections(): EventStream<ConnectionInfo[]> {
    return this.connEvents;
  }

  closeConnection(id: string): Promise<void> {
    return NativeEngine.ni<void>('closeConnection');
  }

  closeAll(): Promise<void> {
    return NativeEngine.ni<void>('closeAll');
  }

  recentHosts(limit: number): EventStream<ConnectionInfo[]> {
    return this.hostEvents;
  }

  connectionTrace(host: string): Promise<ConnectionTrace> {
    return NativeEngine.ni<ConnectionTrace>('connectionTrace');
  }

  overrideHost(host: string, target: TraceTarget, sceneId: string | undefined, persistent: boolean): Promise<void> {
    return NativeEngine.ni<void>('overrideHost');
  }

  logs(): EventStream<LogLine> {
    return this.logEvents;
  }

  setLogLevel(level: LogLevel): Promise<void> {
    return NativeEngine.ni<void>('setLogLevel');
  }

  settings(): StateStream<Settings> {
    return this.settingsState;
  }

  updateSettings(patch: Settings): Promise<void> {
    return NativeEngine.ni<void>('updateSettings');
  }

  storage(): Promise<StorageInfo> {
    return NativeEngine.ni<StorageInfo>('storage');
  }

  localProxyCredential(): Promise<string> {
    return NativeEngine.ni<string>('localProxyCredential');
  }

  resetLocalProxyCredential(): Promise<string> {
    return NativeEngine.ni<string>('resetLocalProxyCredential');
  }

  // ── 9. 命令 ──────────────────────────────────────────────────────────────
  commandSuggestions(input: string): Promise<CommandSuggestion[]> {
    return NativeEngine.ni<CommandSuggestion[]>('commandSuggestions');
  }
}
