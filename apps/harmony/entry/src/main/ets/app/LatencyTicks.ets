/*
 * 场景 sheet 候选列表顶部的延迟刻度条（设计规范 §9.6，评审 J-6；同 iOS LatencyTickBar）的纯逻辑：
 * 横轴 0–600 ms 线性（> 600 贴右端）；每个已测候选一根短刻（≥ 200 ms 琥珀），当前出口加高、强调色；
 * 超时不画、计入“超时 n”；未测不画。
 */
import { NodeId, NodeSummary } from '../engine/Model';
import { ZLatency } from '../generated/ZTokens';

export const TICK_RANGE_MS: number = 600;

export interface Tick {
  id: NodeId;
  ms: number;
  slow: boolean;
  selected: boolean;
}

export interface TickSummary {
  /** 未选中的在前、选中的最后（画在最上层）。 */
  ticks: Tick[];
  timeouts: number;
  underThreshold: number;
  total: number;
}

export class LatencyTicks {
  static summarize(candidates: NodeSummary[], selectedId: NodeId | undefined): TickSummary {
    const ticks: Tick[] = [];
    let sel: Tick | undefined = undefined;
    let timeouts = 0;
    let under = 0;
    for (const n of candidates) {
      const ms = n.latencyMs;
      if (ms === undefined) {
        continue;
      }
      if (ms < 0) {
        timeouts++;
        continue;
      }
      if (ms < ZLatency.slow) {
        under++;
      }
      const t: Tick = { id: n.id, ms: ms, slow: ms >= ZLatency.slow, selected: n.id === selectedId };
      if (t.selected) {
        sel = t;
      } else {
        ticks.push(t);
      }
    }
    if (sel !== undefined) {
      ticks.push(sel);
    }
    return { ticks: ticks, timeouts: timeouts, underThreshold: under, total: candidates.length };
  }

  /** 0–600 ms 线性映射到宽度（两端各留 0.5，> 600 贴右端）；返回刻度中心 x。 */
  static x(ms: number, width: number): number {
    const t = Math.min(Math.max(ms, 0), TICK_RANGE_MS) / TICK_RANGE_MS;
    return 0.5 + (width - 1) * t;
  }
}
