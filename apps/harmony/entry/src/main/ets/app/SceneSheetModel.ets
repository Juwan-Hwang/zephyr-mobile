/*
 * 场景 sheet 的纯逻辑（M1-5 / U9，对照 Android ui/scene/SceneSheet.kt + SceneFunnel.kt、iOS Scene/SceneSheet）：
 * - 候选池按延迟排序（未测 / 超时排后），列表只显示最快 12 个；池大小是导语里的“M 个节点”。
 * - 漏斗（§15.c nodeFunnel，阈值 300 ms）只在 Zephyr 优选（来源不是订阅分组）时出现；新鲜度 = 设置 › 结果保留（至少 1 h）。
 * - 导语：有漏斗用漏斗的 sourceCount / poolSize；否则订阅数 + 候选数；只有订阅数时只说订阅数；都没有不显示。
 * - 检测频率：latencyTtlHours（0 = 默认 24），24 h 读“每天”，testOnWifiOnly 时补“（仅 Wi‑Fi）”。
 * - 漏斗条宽：对数刻度，1 → 12vp、最大一步 → 160vp，取平方（原型 58 / 30 / 13 / 6 % 的观感）。
 * 不依赖 ArkUI，node / ohosTest 可测。
 */
import { NodeFunnel, NodeSummary, Scene, SceneException, SceneKind, SceneSource, Settings } from '../engine/Model';

export const FUNNEL_THRESHOLD_MS: number = 300;
export const SHEET_POOL_LIMIT: number = 12;
const HOUR_MS: number = 3600000;

export enum LedeKind {
  NONE = 'none',
  /** “检测自 N 个订阅中的 M 个节点” */
  POOL = 'pool',
  /** “检测自 N 个订阅” */
  SOURCES = 'sources'
}

export class Lede {
  kind: LedeKind;
  sources: number;
  pool: number;

  constructor(kind: LedeKind, sources: number, pool: number) {
    this.kind = kind;
    this.sources = sources;
    this.pool = pool;
  }
}

export class FunnelStepValue {
  count: number;
  /** 0 全部 · 1 已测速 · 2 可连通 · 3 延迟低于阈值 */
  step: number;

  constructor(count: number, step: number) {
    this.count = count;
    this.step = step;
  }
}

function latencyKey(n: NodeSummary): number {
  return n.latencyMs !== undefined && n.latencyMs >= 0 ? n.latencyMs : Number.MAX_SAFE_INTEGER;
}

export class SceneSheetModel {
  /** 来源是 Zephyr 优选（auto / manual），漏斗只在此时出现。 */
  static pooled(s: Scene): boolean {
    return s.source !== SceneSource.SUBSCRIPTION_GROUP;
  }

  /** 稳定排序：有延迟的在前。 */
  static sortByLatency(list: NodeSummary[]): NodeSummary[] {
    return list.slice().sort((a: NodeSummary, b: NodeSummary) => latencyKey(a) - latencyKey(b));
  }

  /** 列表显示的候选（最快 12 个）。 */
  static shownPool(sorted: NodeSummary[]): NodeSummary[] {
    return sorted.slice(0, SHEET_POOL_LIMIT);
  }

  /** §15.e：结果保留 → 漏斗 maxAgeMs，至少 1 h。 */
  static funnelMaxAgeMs(settings: Settings): number {
    return Math.max(1, settings.latencyTtlHours) * HOUR_MS;
  }

  static lede(pooled: boolean, funnel: NodeFunnel | undefined, subs: number, candidates: number): Lede {
    if (pooled && funnel !== undefined && funnel.poolSize > 0) {
      return new Lede(LedeKind.POOL, funnel.sourceCount, funnel.poolSize);
    }
    if (subs > 0 && candidates > 0) {
      return new Lede(LedeKind.POOL, subs, candidates);
    }
    if (subs > 0) {
      return new Lede(LedeKind.SOURCES, subs, 0);
    }
    return new Lede(LedeKind.NONE, 0, 0);
  }

  /** 漏斗是否显示（同 Android `funnel?.takeIf { pooled && it.poolSize > 0 }`）。 */
  static showFunnel(pooled: boolean, funnel: NodeFunnel | undefined): boolean {
    return pooled && funnel !== undefined && funnel.poolSize > 0;
  }

  static funnelSteps(f: NodeFunnel): FunnelStepValue[] {
    return [
      new FunnelStepValue(f.poolSize, 0), new FunnelStepValue(f.tested, 1), new FunnelStepValue(f.reachable, 2),
      new FunnelStepValue(f.underThreshold, 3)
    ];
  }

  /** 对数刻度条宽（vp）。 */
  static barWidth(n: number, top: number): number {
    const minW = 12;
    const maxW = 160;
    if (top <= 1) {
      return maxW;
    }
    let t = Math.log(Math.max(n, 1)) / Math.log(top);
    t = Math.min(1, Math.max(0, t));
    return minW + (maxW - minW) * t * t;
  }

  static funnelTop(steps: FunnelStepValue[]): number {
    let top = 1;
    for (const s of steps) {
      top = Math.max(top, s.count);
    }
    return top;
  }

  /** 检测频率的小时数：0 = 默认 24。 */
  static retestHours(settings: Settings): number {
    return settings.latencyTtlHours > 0 ? settings.latencyTtlHours : 24;
  }

  /** “节点不可用时”：AI 场景询问，其余自动切换。 */
  static asksOnFailure(s: Scene): boolean {
    return s.kind === SceneKind.AI;
  }

  /** 切到 Zephyr 优选后 AI 场景收起 sheet（同 Android AppRoot onSource）。 */
  static closesAfterSource(s: Scene, to: SceneSource): boolean {
    return s.kind === SceneKind.AI && to === SceneSource.AUTO;
  }

  /** 候选行上的例外标记：钉在该节点的第一个例外的应用名。 */
  static pinnedApp(s: Scene, n: NodeSummary): string | undefined {
    const e = s.exceptions.find((x: SceneException) => x.node.id === n.id);
    return e !== undefined ? e.app : undefined;
  }
}
