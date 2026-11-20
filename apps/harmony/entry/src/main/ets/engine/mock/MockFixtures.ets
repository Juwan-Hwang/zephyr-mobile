import {
  CommandKind, CommandSuggestion, ConnectionInfo, ConnectionState, ConnectionStatus, ConnectionTrace, GroupType, LogLevel,
  LogLine, NodeSummary, PolicyGroup, ProxyMode, Scene, SceneKind, SceneSource, Subscription, SubscriptionDiff
} from '../Model';
import { MockCatalog } from './MockCatalog';
import { MockRules } from './MockRules';
import { NodeQuery } from './NodeQuery';

/*
 * 原型里手写的固定值（contract/mock-spec.md §5–6），逐项对照 Android MockFixtures.kt。
 * 场景池节点在目录 id 空间之外（≥ POOL_BASE）。
 */

const HOUR_MS: number = 3600000;
const DAY_MS: number = 86400000;
const GB: number = 1000000000;

/** Java/Kotlin `String.hashCode()`（UTF‑16 码元，32 位有符号），跨端同值。 */
export function javaHash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  }
  return h;
}

/** NodeSummary 拷贝并替换延迟（ArkTS 无对象展开）。 */
export function withLatency(s: NodeSummary, latencyMs: number | undefined): NodeSummary {
  const c: NodeSummary = {
    id: s.id,
    name: s.name,
    region: s.region,
    city: s.city,
    carrier: s.carrier,
    tag: s.tag,
    protocol: s.protocol,
    multiplier: s.multiplier,
    latencyMs: latencyMs
  };
  return c;
}

/** 千分位（Kotlin "%,d"）。 */
export function groupThousands(n: number): string {
  const neg = n < 0;
  let s = String(Math.floor(Math.abs(n)));
  let out = '';
  while (s.length > 3) {
    out = ',' + s.substring(s.length - 3) + out;
    s = s.substring(0, s.length - 3);
  }
  return (neg ? '-' : '') + s + out;
}

// ── 应用（Android engine/Apps.kt 的子集：Mock 只需 id → 名字 / 场景）────────────
export class MockApp {
  id: string;
  name: string;
  kind: SceneKind;
  aliases: string[];

  constructor(id: string, name: string, kind: SceneKind, aliases: string[]) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.aliases = aliases;
  }
}

export class MockApps {
  static readonly ALL: MockApp[] = [
    new MockApp('chatgpt', 'GPT', SceneKind.AI, ['chatgpt', 'gpt', 'openai']),
    new MockApp('claude', 'Claude', SceneKind.AI, ['claude', 'anthropic']),
    new MockApp('gemini', 'Gemini', SceneKind.AI, ['gemini', '谷歌ai']),
    new MockApp('perplexity', 'Perplexity', SceneKind.AI, ['perplexity']),
    new MockApp('grok', 'Grok', SceneKind.AI, ['grok']),
    new MockApp('netflix', 'Netflix', SceneKind.VIDEO, ['netflix', '奈飞', '网飞']),
    new MockApp('youtube', 'YouTube', SceneKind.VIDEO, ['youtube', '油管']),
    new MockApp('disney', 'Disney+', SceneKind.VIDEO, ['disney+', 'disney', '迪士尼']),
    new MockApp('max', 'Max', SceneKind.VIDEO, ['hbo max', 'hbo']),
    new MockApp('primevideo', 'Prime Video', SceneKind.VIDEO, ['prime video', 'primevideo'])
  ];

  static byId(id: string): MockApp | undefined {
    return MockApps.ALL.find((a: MockApp) => a.id === id);
  }

  static nameOf(id: string): string {
    const a = MockApps.byId(id);
    return a !== undefined ? a.name : id;
  }
}

// ── 场景 ─────────────────────────────────────────────────────────────────
class PoolNode {
  summary: NodeSummary;
  ip: string;
  latency: number;

  constructor(summary: NodeSummary, ip: string, latency: number) {
    this.summary = summary;
    this.ip = ip;
    this.latency = latency;
  }
}

/** 场景池 id 起点：模块常量（poolNode 在 MockScenes 静态初始化中调用，不能引用 MockScenes 自身）。 */
const POOL_BASE: number = 9000000000;

function poolNode(seq: number, region: string, city: string, name: string, ip: string, latency: number,
  protocol?: string, tag?: string): PoolNode {
  const s: NodeSummary = {
    id: POOL_BASE + seq,
    name: name,
    region: region,
    city: city,
    protocol: protocol ?? 'VLESS',
    tag: tag ?? 'IPLC',
    latencyMs: latency
  };
  return new PoolNode(s, ip, latency);
}

export class MockScenes {
  static readonly POOL_BASE: number = POOL_BASE;

  private static readonly POOL: PoolNode[] = [
    poolNode(0, 'SG', '新加坡', '新加坡 01', '198.51.100.6', 71),
    poolNode(1, 'SG', '新加坡', '新加坡 02', '198.51.100.7', 63),
    poolNode(2, 'SG', '新加坡', '新加坡 03', '198.51.100.8', 88, 'Hy2'),
    poolNode(3, 'JP', '东京', '东京 01', '203.0.113.59', 66),
    poolNode(4, 'JP', '东京', '东京 02', '203.0.113.60', 74, 'TUIC'),
    poolNode(5, 'JP', '东京', '东京 03', '203.0.113.61', 61),
    poolNode(6, 'JP', '大阪', '大阪 01', '203.0.113.70', 79, 'Hy2'),
    poolNode(7, 'HK', '香港', '香港 HKT', '203.0.113.24', 38, undefined, '原生'),
    poolNode(8, 'HK', '香港', '香港 HKBN', '203.0.113.25', 42, undefined, '家宽'),
    poolNode(9, 'HK', '香港', '香港 PCCW', '203.0.113.26', 47),
    poolNode(10, 'TW', '台北', 'TW-Fixed-01', '198.51.100.41', 48, 'Trojan', '原生'),
    poolNode(11, 'TW', '台北', '台北 HiNet 01', '198.51.100.42', 52),
    poolNode(12, 'US', '洛杉矶', 'US-Fixed-01', '203.0.113.24', 152, 'Trojan', '原生'),
    poolNode(13, 'US', '圣何塞', '圣何塞 01', '203.0.113.90', 164, 'TUIC'),
    poolNode(14, 'KR', '首尔', '首尔 01', '198.51.100.77', 69)
  ];

  static readonly SG_02: NodeSummary = MockScenes.POOL[1].summary;
  static readonly TOKYO_03: NodeSummary = MockScenes.POOL[5].summary;
  static readonly HK_HKT: NodeSummary = MockScenes.POOL[7].summary;
  static readonly TW_FIXED: NodeSummary = MockScenes.POOL[10].summary;
  static readonly US_FIXED: NodeSummary = MockScenes.POOL[12].summary;

  private static find(id: number): PoolNode | undefined {
    return MockScenes.POOL.find((p: PoolNode) => p.summary.id === id);
  }

  static byId(id: number): NodeSummary | undefined {
    const p = MockScenes.find(id);
    return p !== undefined ? p.summary : undefined;
  }

  static exitIp(id: number): string | undefined {
    const p = MockScenes.find(id);
    return p !== undefined ? p.ip : undefined;
  }

  static latency(id: number): number | undefined {
    const p = MockScenes.find(id);
    return p !== undefined ? p.latency : undefined;
  }

  static pool(region?: string): NodeSummary[] {
    const r = region === undefined ? undefined : region.toUpperCase();
    return MockScenes.POOL.map((p: PoolNode) => p.summary)
      .filter((s: NodeSummary) => r === undefined || s.region.toUpperCase() === r);
  }

  static initial(now: number): Scene[] {
    const tested = now - 2 * HOUR_MS;
    const ai: Scene = {
      id: 'ai', kind: SceneKind.AI, name: 'AI', available: 9, selected: MockScenes.SG_02, exitIp: '198.51.100.7',
      source: SceneSource.AUTO, testedAt: tested,
      exceptions: [{ app: 'Claude', appId: 'claude', node: MockScenes.US_FIXED }], services: []
    };
    const video: Scene = {
      id: 'video', kind: SceneKind.VIDEO, name: '视频', available: 22, selected: MockScenes.HK_HKT, exitIp: '203.0.113.24',
      source: SceneSource.AUTO, testedAt: tested, note: 'Netflix 完整片库', exceptions: [], services: []
    };
    const other: Scene = {
      id: 'other', kind: SceneKind.OTHER, name: '其他', available: 0, selected: MockScenes.TW_FIXED, exitIp: '198.51.100.41',
      source: SceneSource.SUBSCRIPTION_GROUP, testedAt: tested, exceptions: [], services: []
    };
    return [ai, video, other];
  }
}

// ── 订阅 ─────────────────────────────────────────────────────────────────
function diff(added: number, removed: number, rules: number): SubscriptionDiff {
  const d: SubscriptionDiff = { addedNodes: added, removedNodes: removed, ruleChanges: rules, overridesKept: true, scenesRetested: true };
  return d;
}

export class MockSubscriptions {
  static readonly TOTAL_COUNT: number = 214;

  static initial(now: number): Subscription[] {
    const nebula: Subscription = {
      id: 'nebula', name: 'Nebula Cloud', url: 'https://nebula.example/api/v1/client/•••',
      nodeCount: 8204, usedBytes: 113600000000, totalBytes: 200 * GB, remainingBytes: 86400000000,
      expiresAt: now + 26 * DAY_MS, updatedAt: now - 2 * HOUR_MS, autoUpdateHours: 12,
      lastDiff: diff(1204, 318, 0)
    };
    const orbit: Subscription = {
      id: 'orbit', name: 'Orbit', url: 'https://orbit.example/sub/•••',
      nodeCount: 3118, usedBytes: 88 * GB, totalBytes: 100 * GB, remainingBytes: 12 * GB,
      expiresAt: now + 3 * DAY_MS, updatedAt: now - 5 * HOUR_MS, autoUpdateHours: 12
    };
    return [nebula, orbit];
  }

  static diffFor(s: Subscription): SubscriptionDiff {
    if (s.id === 'nebula') {
      return diff(1204, 318, 0);
    }
    const h = MockCatalog.hsh(13, javaHash(s.id) & 0x7FFFFFFF);
    return diff(h % 40, h % 17, h % 3);
  }

  static redact(url: string): string {
    const i = url.indexOf('?');
    const base = i >= 0 ? url.substring(0, i) : url;
    const cut = base.lastIndexOf('/');
    return cut > 8 ? base.substring(0, cut + 1) + '•••' : base;
  }
}

// ── 策略组 ───────────────────────────────────────────────────────────────
function group(name: string, type: GroupType, selected: string | undefined, memberCount: number, testedAt?: number): PolicyGroup {
  const g: PolicyGroup = { name: name, type: type, selected: selected, memberCount: memberCount, testedAt: testedAt };
  return g;
}

export class MockGroups {
  static initial(now: number): PolicyGroup[] {
    return [
      group('节点选择', GroupType.SELECT, '新加坡 02', 512, now - 2 * HOUR_MS),
      group('自动选择', GroupType.URL_TEST, '香港 HKT', 512, now - 600000),
      group('故障转移', GroupType.FALLBACK, 'TW-Fixed-01', 64, now - 600000),
      group('AI', GroupType.SELECT, '新加坡 02', 138, now - 2 * HOUR_MS),
      group('流媒体', GroupType.SELECT, '香港 HKT', 96, now - 2 * HOUR_MS),
      group('负载均衡', GroupType.LOAD_BALANCE, undefined, 32)
    ];
  }

  /** 成员按地区交错，每组都是真实感的混合。 */
  static member(groupName: string, k: number): NodeSummary {
    const salt = javaHash(groupName) & 0xFF;
    const r = (k + salt) % 6;
    const j = Math.floor(k / 6) + salt;
    return MockCatalog.summary(r, j);
  }
}

// ── 连接 / 轨迹 ──────────────────────────────────────────────────────────
class BaseConn {
  host: string;
  scene: string | undefined;
  node: string;
  down: number;
  up: number;

  constructor(host: string, scene: string | undefined, node: string, down: number, up: number) {
    this.host = host;
    this.scene = scene;
    this.node = node;
    this.down = down;
    this.up = up;
  }
}

export class MockConnections {
  private static readonly BASE: BaseConn[] = [
    new BaseConn('claude.ai', 'AI', 'US-Fixed-01', 2100000, 180000),
    new BaseConn('nflxvideo.net', '视频', '香港 HKT', 184000000, 2400000),
    new BaseConn('gemini.google.com', 'AI', '新加坡 02', 640000, 90000),
    new BaseConn('github.com', '其他', 'TW-Fixed-01', 12000000, 1100000),
    new BaseConn('qq.com', undefined, '直连', 3400000, 410000),
    new BaseConn('api.openai.com', 'AI', '新加坡 02', 1300000, 220000),
    new BaseConn('i.ytimg.com', '视频', '香港 HKT', 22000000, 300000)
  ];

  private static sceneId(scene: string | undefined): string | undefined {
    switch (scene) {
      case 'AI':
        return 'ai';
      case '视频':
        return 'video';
      case '其他':
        return 'other';
      default:
        return undefined;
    }
  }

  /** 契约 §13 固定轨迹（原型 9:41）；只认前 5 个主机。 */
  static trace(host: string, now: number): ConnectionTrace | undefined {
    const i = MockConnections.BASE.findIndex((c: BaseConn) => c.host === host);
    if (i < 0 || i > 4) {
      return undefined;
    }
    const c = MockConnections.BASE[i];
    if (host === 'claude.ai') {
      const node: NodeSummary = { id: -101, name: 'US-Fixed-01', region: 'US', protocol: 'VLESS', latencyMs: 162 };
      const t: ConnectionTrace = {
        host: host, lastSeenAt: now - 3000, connections: 17, totalBytes: 2100000,
        rule: 'DOMAIN-SUFFIX,claude.ai', ruleSource: 'Nebula Cloud', scene: 'ai', sceneSource: 'Zephyr 优选',
        node: node, via: 'US Fixed IP · 固定', exitIp: '203.0.113.24', exitRegion: '美国', exitStableDays: 7
      };
      return t;
    }
    let node: NodeSummary | undefined = undefined;
    if (c.scene !== undefined) {
      const region = c.node.startsWith('TW') ? 'TW' : (c.node.includes('香港') ? 'HK' : 'SG');
      const n: NodeSummary = { id: -102 - i, name: c.node, region: region, protocol: 'VLESS' };
      node = n;
    }
    const t: ConnectionTrace = {
      host: host, lastSeenAt: now - (i + 1) * 3000, connections: 3 + i * 2, totalBytes: c.down + c.up,
      rule: c.scene === undefined ? 'GEOSITE,cn' : `DOMAIN-SUFFIX,${host}`,
      ruleSource: c.scene === undefined ? 'geosite:cn' : 'Nebula Cloud',
      scene: MockConnections.sceneId(c.scene),
      sceneSource: c.scene !== undefined ? 'Zephyr 优选' : undefined,
      node: node
    };
    return t;
  }

  static at(start: number, t: number): ConnectionInfo[] {
    return MockConnections.BASE.map((c: BaseConn, i: number) => {
      const grow = 1.0 + t * (0.01 + i * 0.002);
      const info: ConnectionInfo = {
        id: `c${i}`, host: c.host, scene: c.scene, node: c.node,
        upBytes: Math.floor(c.up * grow), downBytes: Math.floor(c.down * grow), startedAt: start - (i + 1) * 3000
      };
      return info;
    });
  }
}

// ── 日志 ─────────────────────────────────────────────────────────────────
class LogTemplate {
  level: LogLevel;
  message: string;

  constructor(level: LogLevel, message: string) {
    this.level = level;
    this.message = message;
  }
}

export class MockLogs {
  private static readonly MSGS: LogTemplate[] = [
    new LogTemplate(LogLevel.INFO, '[TCP] 198.18.0.1:53412 --> claude.ai:443 match DomainSuffix(claude.ai) using AI[US-Fixed-01]'),
    new LogTemplate(LogLevel.INFO, '[TCP] 198.18.0.1:53418 --> nflxvideo.net:443 match DomainSuffix(netflix.com) using 视频[香港 HKT]'),
    new LogTemplate(LogLevel.DEBUG, '[DNS] github.com --> 140.82.112.4 (fake-ip 198.18.0.23)'),
    new LogTemplate(LogLevel.INFO, '[UDP] 198.18.0.1:61001 --> 8.8.8.8:53 match Match using 其他[TW-Fixed-01]'),
    new LogTemplate(LogLevel.WARNING, '[Provider] Orbit pull: 304 not modified'),
    new LogTemplate(LogLevel.INFO, '[TCP] 198.18.0.1:53501 --> doubleclick.net:443 match DomainKeyword(doubleclick) using REJECT'),
    new LogTemplate(LogLevel.ERROR, '[TCP] dial 新加坡 03 (198.51.100.8:443) error: i/o timeout')
  ];

  static line(i: number, now: number): LogLine {
    const m = MockLogs.MSGS[MockCatalog.hsh(9, i) % MockLogs.MSGS.length];
    const l: LogLine = { at: now, level: m.level, message: m.message };
    return l;
  }
}

// ── 指令建议（§16.d，v1 可选）──────────────────────────────────────────────
class ServiceAlias {
  key: string;
  name: string;

  constructor(key: string, name: string) {
    this.key = key;
    this.name = name;
  }
}

function cmd(kind: CommandKind, title: string, subtitle: string | undefined, payload: string): CommandSuggestion {
  const c: CommandSuggestion = { kind: kind, title: title, subtitle: subtitle, payload: payload };
  return c;
}

export class MockCommands {
  private static readonly DOMAINISH: RegExp = new RegExp('^[a-z0-9-]+(\\.[a-z0-9-]+)+$');
  private static readonly SERVICES: ServiceAlias[] = [
    new ServiceAlias('gemini', 'Gemini'),
    new ServiceAlias('gpt', 'GPT'),
    new ServiceAlias('chatgpt', 'GPT'),
    new ServiceAlias('claude', 'Claude'),
    new ServiceAlias('netflix', 'Netflix'),
    new ServiceAlias('youtube', 'YouTube')
  ];

  static suggest(raw: string, scenes: Scene[], conn: ConnectionState): CommandSuggestion[] {
    const input = raw.trim().toLowerCase();
    const out: CommandSuggestion[] = [];
    if (input.length === 0) {
      const global = conn.mode === ProxyMode.GLOBAL;
      out.push(cmd(CommandKind.TOGGLE_CONNECTION, conn.status === ConnectionStatus.CONNECTED ? '断开连接' : '连接', undefined, 'toggle'));
      out.push(cmd(CommandKind.SWITCH_MODE, global ? '使用规则模式' : '全局模式', undefined, global ? 'rule' : 'global'));
      out.push(cmd(CommandKind.OPEN_NODE_QUERY, '最快的日本节点', 'JP', 'jp'));
      out.push(cmd(CommandKind.TEST_RULE, 'claude.ai 走哪里？', undefined, 'claude.ai'));
      out.push(cmd(CommandKind.OPEN_PAGE, '资料库', undefined, 'library'));
      return out;
    }
    if (input === '全局' || input === '全局模式' || input === 'global') {
      out.push(cmd(CommandKind.SWITCH_MODE, '全局模式', '所有流量经由一个节点', 'global'));
    } else if (input === '规则' || input === '规则模式' || input === 'rule') {
      out.push(cmd(CommandKind.SWITCH_MODE, '规则模式', '按场景分流', 'rule'));
    } else if (input === '直连' || input === 'direct') {
      out.push(cmd(CommandKind.SWITCH_MODE, '直连模式', '不经过代理', 'direct'));
    }
    if (MockCommands.DOMAINISH.test(input) || MockRules.isIp(input)) {
      out.push(cmd(CommandKind.TEST_RULE, `${input} 走哪里？`, '测试规则', input));
    }
    const svc = MockCommands.SERVICES.find((s: ServiceAlias) => input.includes(s.key));
    const service = svc !== undefined ? svc.name : undefined;
    let stripped = input.replace(new RegExp('走|用|使用|切到|换到', 'g'), ' ');
    for (const s of MockCommands.SERVICES) {
      stripped = stripped.split(s.key).join(' ');
    }
    const q = NodeQuery.build(stripped);
    if (q.groups.length > 0 && q.highlights.length > 0 && q.groups.length < MockCatalog.REGIONS.length) {
      const region = MockCatalog.REGIONS[q.groups[0].region];
      const pool = MockScenes.pool(region.code).sort((a: NodeSummary, b: NodeSummary) =>
        (a.latencyMs ?? Number.MAX_SAFE_INTEGER) - (b.latencyMs ?? Number.MAX_SAFE_INTEGER));
      if (pool.length > 0) {
        const best = pool[0];
        let sceneId = 'global';
        if (service !== undefined) {
          const want = service === 'Netflix' || service === 'YouTube' ? SceneKind.VIDEO : SceneKind.AI;
          const scene = scenes.find((s: Scene) => s.kind === want);
          if (scene !== undefined) {
            sceneId = scene.id;
          }
        }
        out.push(cmd(
          CommandKind.SWITCH_NODE,
          service !== undefined ? `${service} 使用${region.name}节点` : `切换到 ${best.name}`,
          `${pool.length} 个可用，将使用 ${best.name}。`,
          `${sceneId}:${best.id}`
        ));
      }
      out.push(cmd(CommandKind.OPEN_NODE_QUERY, `在节点库中查看「${q.highlights.join(' ')}」`, `${groupThousands(q.total)} 个`, q.query.trim()));
    }
    return out.slice(0, 8);
  }
}
