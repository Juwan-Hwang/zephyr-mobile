/*
 * ArkTS 版 contract/zephyr-engine.md（v0 → v0.4）数据类型，对照 Android core-engine Model.kt / iOS ZephyrKit。
 * 单位：时间 = 毫秒 Unix 时间戳，速率 = 字节/秒，流量 = 字节，延迟 = 毫秒（undefined = 未测，-1 = 超时）。
 * 枚举值 = 契约序列化名（snake_case），JSON 与 core-ohos 直接互通。
 * NodeId 用 number：Mock 的 id = region * 1e8 + index、真实核心的指纹 id 都在 2^53 以内（core-ohos 以 f64 传）。
 */

export type NodeId = number;

export const LATENCY_TIMEOUT: number = -1;

// ── 1. 连接 ──────────────────────────────────────────────────────────────
export enum ConnectionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  DISCONNECTING = 'disconnecting',
  FAILED = 'failed'
}

export enum ProxyMode {
  RULE = 'rule',
  GLOBAL = 'global',
  DIRECT = 'direct'
}

export enum NetworkKind {
  WIFI = 'wifi',
  CELLULAR = 'cellular',
  ETHERNET = 'ethernet',
  OTHER = 'other'
}

export enum ErrorCode {
  NOT_RUNNING = 'not_running',
  VPN_PERMISSION_DENIED = 'vpn_permission_denied',
  NETWORK_UNAVAILABLE = 'network_unavailable',
  SUBSCRIPTION_INVALID = 'subscription_invalid',
  SUBSCRIPTION_FETCH_FAILED = 'subscription_fetch_failed',
  NODE_NOT_FOUND = 'node_not_found',
  SCENE_NOT_FOUND = 'scene_not_found',
  GROUP_NOT_FOUND = 'group_not_found',
  RULE_INPUT_INVALID = 'rule_input_invalid',
  CORE_CRASHED = 'core_crashed',
  STORAGE_FULL = 'storage_full',
  CANCELLED = 'cancelled',
  STALE_TOKEN = 'stale_token',
  SUBSCRIPTION_NOT_FOUND = 'subscription_not_found',
  INTERNAL = 'internal'
}

/** 契约 §0.5：文案不由引擎给，UI 按 code 本地化；message 只进日志。 */
export interface ZephyrErrorInfo {
  code: ErrorCode;
  message: string;
}

export interface NetworkInfo {
  kind: NetworkKind;
  name?: string;
  trusted: boolean;
}

export interface ConnectionState {
  status: ConnectionStatus;
  mode: ProxyMode;
  since?: number;
  globalNodeId?: NodeId;
  network?: NetworkInfo;
  error?: ZephyrErrorInfo;
}

// ── 2. 流量 ──────────────────────────────────────────────────────────────
export interface TrafficSample {
  at: number;
  upBps: number;
  downBps: number;
}

export interface UsageSummary {
  todayBytes: number;
  regionsToday: number;
  onlineMillisToday: number;
  fastestLatencyMs?: number;
  hourly: number[];
}

// ── 3. 场景 ──────────────────────────────────────────────────────────────
export enum SceneKind {
  AI = 'ai',
  VIDEO = 'video',
  OTHER = 'other',
  CUSTOM = 'custom'
}

export enum SceneSource {
  AUTO = 'auto',
  MANUAL = 'manual',
  SUBSCRIPTION_GROUP = 'subscription_group'
}

export interface NodeSummary {
  id: NodeId;
  name: string;
  region: string;
  city?: string;
  carrier?: string;
  tag?: string;
  protocol: string;
  multiplier?: number;
  latencyMs?: number;
}

export interface SceneException {
  app: string;
  appId: string;
  node: NodeSummary;
}

export interface ServiceHealth {
  appId: string;
  name: string;
  ok: boolean;
  checkedAt: number;
}

export interface Scene {
  id: string;
  kind: SceneKind;
  name: string;
  available: number;
  selected: NodeSummary;
  exitIp?: string;
  source: SceneSource;
  testedAt?: number;
  note?: string;
  exceptions: SceneException[];
  services: ServiceHealth[];
  /** §15.h：'uhd' = 只用 4K 节点；undefined = 全部。 */
  nodeFilter?: string;
}

export interface ExitChange {
  sceneId?: string;
  fromRegion: string;
  fromIp?: string;
  toRegion: string;
  toIp?: string;
  affectedApps: string[];
  unchangedApps: string[];
}

/** §15.d 平台本地扫描进度。 */
export interface ScanProgress {
  done: number;
  total: number;
}

/** §15.c 场景漏斗。 */
export interface NodeFunnel {
  sourceCount: number;
  poolSize: number;
  tested: number;
  reachable: number;
  underThreshold: number;
  thresholdMs: number;
}

// ── 4. 策略组 ────────────────────────────────────────────────────────────
export enum GroupType {
  SELECT = 'select',
  URL_TEST = 'url_test',
  FALLBACK = 'fallback',
  LOAD_BALANCE = 'load_balance',
  RELAY = 'relay'
}

export interface PolicyGroup {
  name: string;
  type: GroupType;
  selected?: string;
  memberCount: number;
  testedAt?: number;
}

// ── 5. 节点库 ────────────────────────────────────────────────────────────
export interface RegionSection {
  region: string;
  name: string;
  count: number;
  /** 含分区头行 */
  rowOffset: number;
}

export interface NodeIndex {
  total: number;
  sections: RegionSection[];
  testedCount: number;
}

export interface NodeQueryResult {
  query: string;
  total: number;
  sections: RegionSection[];
  highlights: string[];
  tookMicros: number;
  token: number;
}

export interface NodePage {
  rows: NodeSummary[];
  offset: number;
  total: number;
}

export interface LatencyUpdate {
  id: NodeId;
  latencyMs: number;
  at: number;
}

export interface NodeDetail {
  summary: NodeSummary;
  server: string;
  port: number;
  subscription: string;
  extra: Record<string, string>;
  latencyMs?: number;
  latencyAt?: number;
}

// ── 6. 规则 ──────────────────────────────────────────────────────────────
export enum LayerKind {
  OVERRIDE = 'override',
  SUBSCRIPTION = 'subscription',
  DOMAIN = 'domain',
  IP = 'ip'
}

export interface RuleLayer {
  index: number;
  kind: LayerKind;
  name: string;
  count: number;
  note: string;
  updatedAt?: number;
}

export interface RuleStats {
  total: number;
  layers: RuleLayer[];
  compiled: boolean;
  diskBytes: number;
}

export interface RuleTrace {
  input: string;
  isIp: boolean;
  /** undefined = 落到 MATCH */
  layerIndex?: number;
  rule: string;
  ruleNo?: number;
  policy: string;
  scene?: Scene;
  exitIp?: string;
  tookMicros: number;
}

// ── 7. 订阅 ──────────────────────────────────────────────────────────────
export interface SubscriptionDiff {
  addedNodes: number;
  removedNodes: number;
  ruleChanges: number;
  overridesKept: boolean;
  scenesRetested: boolean;
}

export interface Subscription {
  id: string;
  name: string;
  url?: string;
  nodeCount: number;
  usedBytes?: number;
  totalBytes?: number;
  remainingBytes?: number;
  expiresAt?: number;
  updatedAt?: number;
  autoUpdateHours: number;
  lastDiff?: SubscriptionDiff;
}

export interface SubscriptionsSummary {
  count: number;
  totalNodes: number;
}

export enum ImportSource {
  URL = 'url',
  CLIPBOARD = 'clipboard',
  QR = 'qr',
  FILE = 'file'
}

// ── 8. 连接、日志、设置 ──────────────────────────────────────────────────
export interface ConnectionInfo {
  id: string;
  host: string;
  app?: string;
  scene?: string;
  node: string;
  upBytes: number;
  downBytes: number;
  startedAt: number;
}

export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARNING = 'warning',
  ERROR = 'error'
}

export function logLevelRank(l: LogLevel): number {
  switch (l) {
    case LogLevel.DEBUG:
      return 0;
    case LogLevel.INFO:
      return 1;
    case LogLevel.WARNING:
      return 2;
    default:
      return 3;
  }
}

export interface LogLine {
  at: number;
  level: LogLevel;
  message: string;
}

export enum Accent {
  BLUE = 'blue',
  GREEN = 'green',
  ORANGE = 'orange',
  PINK = 'pink'
}

export enum Appearance {
  SYSTEM = 'system',
  DARK = 'dark',
  LIGHT = 'light'
}

export enum TunStack {
  SYSTEM = 'system',
  GVISOR = 'gvisor',
  MIXED = 'mixed'
}

export interface DnsSettings {
  fakeIp: boolean;
  nameservers: string[];
  fallback: string[];
  ipv6: boolean;
}

export interface TunSettings {
  stack: TunStack;
  mtu: number;
  ipv6: boolean;
  /** 移动端无效（§16.a⑦），不展示，只为旧数据可解码。 */
  strictRoute: boolean;
}

export interface Settings {
  onDemand: boolean;
  trustedWifi: string[];
  disconnectOnTrusted: boolean;
  localProxyEnabled: boolean;
  localProxyPort: number;
  localProxyAuth: boolean;
  testOnWifiOnly: boolean;
  latencyTtlHours: number;
  autoUpdateHours: number;
  updateOnWifiOnly: boolean;
  showChangesBeforeUpdate: boolean;
  dns: DnsSettings;
  tun: TunSettings;
  accent: Accent;
  appearance: Appearance;
  shareDiagnostics: boolean;
}

/** §16.c 首次安装默认值（Release 与 Mock 相同；演示值如 trustedWifi=["家"] 不进这里）。 */
export function defaultSettings(): Settings {
  const s: Settings = {
    onDemand: true,
    trustedWifi: [],
    disconnectOnTrusted: true,
    localProxyEnabled: false,
    localProxyPort: 7890,
    localProxyAuth: true,
    testOnWifiOnly: true,
    latencyTtlHours: 24,
    autoUpdateHours: 12,
    updateOnWifiOnly: true,
    showChangesBeforeUpdate: false,
    dns: {
      fakeIp: true,
      nameservers: ['https://dns.alidns.com/dns-query', 'https://doh.pub/dns-query'],
      fallback: ['https://1.1.1.1/dns-query'],
      ipv6: false
    },
    tun: { stack: TunStack.GVISOR, mtu: 9000, ipv6: false, strictRoute: true },
    accent: Accent.BLUE,
    appearance: Appearance.SYSTEM,
    shareDiagnostics: false
  };
  return s;
}

/** 浅拷贝 + 嵌套对象拷贝，供“全量写回”式 updateSettings 使用。 */
export function copySettings(s: Settings): Settings {
  const c: Settings = {
    onDemand: s.onDemand,
    trustedWifi: s.trustedWifi.slice(),
    disconnectOnTrusted: s.disconnectOnTrusted,
    localProxyEnabled: s.localProxyEnabled,
    localProxyPort: s.localProxyPort,
    localProxyAuth: s.localProxyAuth,
    testOnWifiOnly: s.testOnWifiOnly,
    latencyTtlHours: s.latencyTtlHours,
    autoUpdateHours: s.autoUpdateHours,
    updateOnWifiOnly: s.updateOnWifiOnly,
    showChangesBeforeUpdate: s.showChangesBeforeUpdate,
    dns: {
      fakeIp: s.dns.fakeIp,
      nameservers: s.dns.nameservers.slice(),
      fallback: s.dns.fallback.slice(),
      ipv6: s.dns.ipv6
    },
    tun: { stack: s.tun.stack, mtu: s.tun.mtu, ipv6: s.tun.ipv6, strictRoute: s.tun.strictRoute },
    accent: s.accent,
    appearance: s.appearance,
    shareDiagnostics: s.shareDiagnostics
  };
  return c;
}

export interface StorageInfo {
  nodesBytes: number;
  rulesBytes: number;
  freeBytes: number;
}

// ── 9. 命令 ──────────────────────────────────────────────────────────────
export enum CommandKind {
  SWITCH_NODE = 'switch_node',
  SWITCH_MODE = 'switch_mode',
  OPEN_NODE_QUERY = 'open_node_query',
  TEST_RULE = 'test_rule',
  OPEN_PAGE = 'open_page',
  TOGGLE_CONNECTION = 'toggle_connection'
}

export interface CommandSuggestion {
  kind: CommandKind;
  title: string;
  subtitle?: string;
  payload: string;
}

// ── 13. 连接轨迹 ─────────────────────────────────────────────────────────
export enum TraceTarget {
  UNCHANGED = 'unchanged',
  DIRECT = 'direct',
  SCENE = 'scene'
}

export interface TraceOverride {
  target: TraceTarget;
  sceneId?: string;
  persistent: boolean;
}

export interface ConnectionTrace {
  host: string;
  lastSeenAt: number;
  connections: number;
  totalBytes: number;
  rule: string;
  ruleSource?: string;
  scene?: string;
  sceneSource?: string;
  node?: NodeSummary;
  via?: string;
  exitIp?: string;
  exitRegion?: string;
  exitStableDays?: number;
  override?: TraceOverride;
}

// ── 15. 导入载荷 ─────────────────────────────────────────────────────────
export enum ImportPayloadKind {
  ZEPHYR = 'zephyr',
  CLASH_INSTALL = 'clashInstall',
  URL = 'url'
}

export interface ImportItem {
  name?: string;
  url: string;
  autoUpdateHours?: number;
}

export interface ImportPayload {
  kind: ImportPayloadKind;
  items: ImportItem[];
}
