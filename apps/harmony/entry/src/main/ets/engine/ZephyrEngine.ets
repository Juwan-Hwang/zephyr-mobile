import {
  CommandSuggestion, ConnectionInfo, ConnectionState, ConnectionTrace, ErrorCode, ExitChange, ImportItem,
  ImportPayload, ImportSource, LatencyUpdate, LogLevel, LogLine, NodeDetail, NodeFunnel, NodeId, NodeIndex, NodePage,
  NodeFilterPreview, NodeQueryResult, NodeSummary, PolicyGroup, ProxyMode, RuleStats, RuleTrace, ScanProgress, Scene, SceneFailoverNotice, SceneSource,
  Settings, StorageInfo, Subscription, SubscriptionDiff, SubscriptionsSummary, TraceTarget, TrafficSample,
  UsageSummary, ZephyrErrorInfo
} from './Model';
import { EventStream, StateStream } from './Stream';

/**
 * 契约错误：UI 按 code 本地化，message 只进日志（§0.5、§16.b）。
 * 用 class 而不是接口，便于 `e instanceof ZephyrError` 区分平台异常（BusinessError）。
 */
export class ZephyrError extends Error {
  code: ErrorCode;

  constructor(code: ErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'ZephyrError';
    this.code = code;
  }

  toInfo(): ZephyrErrorInfo {
    const info: ZephyrErrorInfo = { code: this.code, message: this.message };
    return info;
  }

  /** 任意异常 → 契约错误；非契约异常一律 internal（§16.b①）。 */
  static from(e: Object | undefined): ZephyrError {
    if (e instanceof ZephyrError) {
      return e;
    }
    if (e instanceof Error) {
      return new ZephyrError(ErrorCode.INTERNAL, e.message);
    }
    return new ZephyrError(ErrorCode.INTERNAL, String(e));
  }
}

/**
 * UI 与核心之间唯一的接缝（contract/zephyr-engine.md），对照 Android `ZephyrEngine.kt`、iOS `ZephyrEngine` 协议。
 * - 列表一律“计数 + 索引 + 分页”，从不返回全量节点 / 规则。
 * - 异步一律 Promise；流见 Stream.ets（StateStream 订阅即回放当前值）。
 * - 三个实现：MockEngine（纯 ArkTS，按 mock-spec 确定性生成）、NativeEngine（经 core-ohos NAPI，桩）、
 *   以后的 RustMockEngine（core-ohos 导出 Rust mock，TODO，见 engine/native/NativeEngine.ets）。
 */
export interface ZephyrEngine {
  /** 'mock' | 'native'，仅用于诊断与 README 里说的“仅界面”提示。 */
  readonly kind: string;

  // 1. 连接（平台层先启动 VPN 扩展，再调 connect）
  connectionState(): StateStream<ConnectionState>;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  /** 平台层（VPN 扩展）连接失败时回写，让 UI 显示失败原因（Android reportConnectFailure 的等价物）。 */
  reportConnectFailure(error: ZephyrError): void;
  setMode(mode: ProxyMode): Promise<void>;
  previewGlobalChange(nodeId: NodeId): Promise<ExitChange>;
  setGlobalNode(id: NodeId): Promise<ExitChange>;

  // 2. 流量
  traffic(): EventStream<TrafficSample>;
  recentTraffic(seconds: number): Promise<TrafficSample[]>;
  usageToday(): Promise<UsageSummary>;

  // 3. 场景
  scenes(): StateStream<Scene[]>;
  sceneCandidates(sceneId: string, region?: string): Promise<NodeSummary[]>;
  previewSceneChange(sceneId: string, nodeId: NodeId): Promise<ExitChange>;
  applySceneChange(sceneId: string, nodeId: NodeId): Promise<void>;
  /** 场景出口探测事件（U8）：UI 只在前台且已连接时订阅。 */
  sceneFailovers(): EventStream<SceneFailoverNotice>;
  retestScene(sceneId: string): Promise<Scene>;
  scanProgress(): StateStream<ScanProgress | undefined>;
  nodeFunnel(maxAgeMs: number, thresholdMs: number): Promise<NodeFunnel | undefined>;
  setSceneSource(sceneId: string, source: SceneSource): Promise<NodeSummary | undefined>;
  setSceneException(sceneId: string, appId: string, nodeId?: NodeId): Promise<void>;
  /** §15.h：预览“只用 4K 节点”；平台据此出确认卡（poolMatching == 0 时禁用）。 */
  previewSceneNodeFilter(sceneId: string, filter: string): Promise<NodeFilterPreview>;
  /** §15.h：持久化过滤（undefined 清除）；从不主动切走当前节点。poolMatching == 0 时抛 rule_input_invalid。 */
  setSceneNodeFilter(sceneId: string, filter: string | undefined): Promise<void>;

  // 4. 策略组（v1 UI 不展示，由场景取代；接口保留，见设计规范 §3）
  policyGroups(): StateStream<PolicyGroup[]>;
  groupMembers(group: string, offset: number, limit: number): Promise<NodePage>;
  selectInGroup(group: string, nodeId: NodeId): Promise<void>;
  testGroup(group: string): Promise<void>;

  // 5. 节点库
  nodeIndex(): Promise<NodeIndex>;
  queryNodes(query: string): Promise<NodeQueryResult>;
  nodeRows(token: number, offset: number, limit: number): Promise<NodePage>;
  node(id: NodeId): Promise<NodeDetail>;
  testLatency(ids: NodeId[]): Promise<void>;
  latencyUpdates(): EventStream<LatencyUpdate[]>;

  // 6. 规则
  ruleStats(): Promise<RuleStats>;
  testRule(input: string): Promise<RuleTrace>;

  // 7. 订阅
  subscriptions(): StateStream<Subscription[]>;
  subscriptionsSummary(): Promise<SubscriptionsSummary>;
  importSubscription(source: ImportSource, payload: string): Promise<Subscription>;
  parseImportPayload(payload: string): ImportPayload;
  importItem(source: ImportSource, item: ImportItem): Promise<Subscription>;
  previewUpdate(id: string): Promise<SubscriptionDiff>;
  updateSubscription(id: string): Promise<SubscriptionDiff>;
  updateAll(): Promise<SubscriptionDiff[]>;
  deleteSubscription(id: string): Promise<void>;

  // 8. 连接、日志、设置
  activeConnections(): EventStream<ConnectionInfo[]>;
  closeConnection(id: string): Promise<void>;
  closeAll(): Promise<void>;
  recentHosts(limit: number): EventStream<ConnectionInfo[]>;
  connectionTrace(host: string): Promise<ConnectionTrace>;
  overrideHost(host: string, target: TraceTarget, sceneId: string | undefined, persistent: boolean): Promise<void>;
  /** 日志按 minLevel 过滤由调用方做（同一条流可被多个页面以不同级别订阅）。 */
  logs(): EventStream<LogLine>;
  /** §16.h：日志页选 debug 时 setLogLevel('debug')，离开时回 info。 */
  setLogLevel(level: LogLevel): Promise<void>;
  settings(): StateStream<Settings>;
  updateSettings(patch: Settings): Promise<void>;
  storage(): Promise<StorageInfo>;
  /** §16.g①：本地代理凭据 "zephyr:<24 位>"。 */
  localProxyCredential(): Promise<string>;
  resetLocalProxyCredential(): Promise<string>;

  // 9. 命令（§16.d：v1 可选）
  commandSuggestions(input: string): Promise<CommandSuggestion[]>;
}
