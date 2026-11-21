/*
 * 连接轨迹的纯逻辑（M1-8 最小版 / U12，对照 Android ui/activity/TraceSheet.kt TraceBody、iOS Activity/TraceView）：
 * - 覆写选项：不变 · 直连 · 其余场景（去掉当前场景，最多 2 个）；当前覆写 → 选中下标；下标 → (target, sceneId)。
 * - 指令面板“X 走哪里？”的输入可能还没有连接记录（connectionTrace 抛错）：退回 testRule 的结果拼一条
 *   只读轨迹（observed = false：不显示“N 个连接 · 字节”，也不给覆写，因为还没有可覆写的连接）。
 * 不依赖 ArkUI，node / ohosTest 可测。
 */
import { ConnectionTrace, RuleTrace, Scene, TraceOverride, TraceTarget } from '../engine/Model';

export const TRACE_OTHER_SCENES: number = 2;

export class TraceChoice {
  target: TraceTarget;
  sceneId: string | undefined;

  constructor(target: TraceTarget, sceneId: string | undefined) {
    this.target = target;
    this.sceneId = sceneId;
  }
}

/** 轨迹 + 是否来自真实连接记录。 */
export class TraceResult {
  trace: ConnectionTrace;
  observed: boolean;

  constructor(trace: ConnectionTrace, observed: boolean) {
    this.trace = trace;
    this.observed = observed;
  }
}

export class TraceModel {
  /** 覆写可选的其他场景（同 Android `scenes.filter { it.id != t.scene }.take(2)`）。 */
  static otherScenes(scenes: Scene[], traceScene: string | undefined): Scene[] {
    return scenes.filter((s: Scene) => s.id !== traceScene).slice(0, TRACE_OTHER_SCENES);
  }

  /** 0 不变 · 1 直连 · 2.. 其他场景（找不到场景时按第一个）。 */
  static selectedIndex(ov: TraceOverride | undefined, others: Scene[]): number {
    if (ov === undefined || ov.target === TraceTarget.UNCHANGED) {
      return 0;
    }
    if (ov.target === TraceTarget.DIRECT) {
      return 1;
    }
    const i = others.findIndex((s: Scene) => s.id === ov.sceneId);
    return 2 + Math.max(0, i);
  }

  static choiceAt(i: number, others: Scene[]): TraceChoice {
    if (i <= 0) {
      return new TraceChoice(TraceTarget.UNCHANGED, undefined);
    }
    if (i === 1 || i - 2 >= others.length) {
      return new TraceChoice(TraceTarget.DIRECT, undefined);
    }
    return new TraceChoice(TraceTarget.SCENE, others[i - 2].id);
  }

  /** 撤销用：覆写之前的状态（没有覆写 = 不变、非持久）。 */
  static undoChoice(before: TraceOverride | undefined): TraceOverride {
    if (before === undefined) {
      const o: TraceOverride = { target: TraceTarget.UNCHANGED, sceneId: undefined, persistent: false };
      return o;
    }
    const o: TraceOverride = { target: before.target, sceneId: before.sceneId, persistent: before.persistent };
    return o;
  }

  /** 规则 “DOMAIN-SUFFIX,claude.ai” → “DOMAIN-SUFFIX, claude.ai”（Android `replace(",", ", ")`）。 */
  static ruleText(rule: string): string {
    return rule.split(',').join(', ');
  }

  /** 没有连接记录时由规则测试拼一条只读轨迹。 */
  static fromRuleTrace(r: RuleTrace): ConnectionTrace {
    const s = r.scene;
    const t: ConnectionTrace = {
      host: r.input, lastSeenAt: 0, connections: 0, totalBytes: 0, rule: r.rule,
      // 场景步：命中场景用场景 id；DIRECT 留空（显示“直连”）；REJECT 等其他策略原样显示。
      scene: s !== undefined ? s.id : (r.policy.toUpperCase() === 'DIRECT' ? undefined : r.policy),
      node: s !== undefined && s.selected.id >= 0 ? s.selected : undefined,
      exitIp: r.exitIp ?? (s !== undefined ? s.exitIp : undefined),
      exitRegion: s !== undefined && s.selected.id >= 0 ? s.selected.region : undefined
    };
    return t;
  }
}
