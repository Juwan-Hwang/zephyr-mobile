/*
 * 首页纯逻辑（M1-6；对照 Android ui/home HomeViewModel / HomeCards / design ZSparkline，iOS Home/GlobalModeCard、
 * AppModel+Actions.globalAlternatives、AppModel+Streams.apply(failover:)）：
 * - SparkRing：最近 SPARK_POINTS（90）个下行速率样本的环（同 HomeViewModel.trafficLive，recentTraffic(90) 回填）；
 * - SparkGeometry：单调三次插值（Fritsch–Carlson，同 ZSparkline），顶部留 15 %、曲线占高 92 %，不低于 0；
 * - GlobalPick：全局模式“更换节点”的建议 = 延迟最低的另一个真实节点（排除策略组 / 内置出站与超时）；
 *   候选优先取 GLOBAL 组成员（同 Android），引擎没有 GLOBAL 组时用非“订阅分组”场景候选的并集（同 iOS）；
 * - HomeSubs：首页订阅卡最多 3 行，其余“更多 N 个订阅”（同 Android SubscriptionsCard）；
 * - Failover：撤销只在吐司期间用户没再换过节点时生效（同 iOS apply(failover:) 的守卫）。
 */
import {
  LATENCY_TIMEOUT, NodeId, NodeSummary, Scene, SceneFailoverNotice, SceneSource, Subscription, TrafficSample
} from '../engine/Model';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export const SPARK_POINTS: number = 90;
export const HOME_SUBS_MAX: number = 3;
export const GLOBAL_GROUP: string = 'GLOBAL';

/** GLOBAL 组里不是出口的成员（同 Android HomeViewModel.NON_NODES）。 */
const NON_NODES: string[] = [
  'SELECTOR', 'URLTEST', 'FALLBACK', 'LOADBALANCE', 'RELAY', 'DIRECT', 'REJECT', 'REJECTDROP', 'PASS', 'COMPATIBLE'
];

export class SparkRing {
  private data: number[] = [];
  private capacity: number;

  constructor(capacity?: number) {
    this.capacity = capacity ?? SPARK_POINTS;
  }

  fill(samples: TrafficSample[]): number[] {
    this.data = samples.slice(Math.max(0, samples.length - this.capacity)).map((t: TrafficSample) => Math.max(0, t.downBps));
    return this.values();
  }

  push(v: number): number[] {
    this.data.push(Math.max(0, v));
    if (this.data.length > this.capacity) {
      this.data.splice(0, this.data.length - this.capacity);
    }
    return this.values();
  }

  clear(): void {
    this.data = [];
  }

  values(): number[] {
    return this.data.slice();
  }
}

export interface SparkPoint {
  x: number;
  y: number;
}

/** 一段三次贝塞尔：两个控制点 + 终点。 */
export interface SparkSegment {
  c1: SparkPoint;
  c2: SparkPoint;
  to: SparkPoint;
}

export interface SparkShape {
  start: SparkPoint;
  segments: SparkSegment[];
  head: SparkPoint;
}

export class SparkGeometry {
  /** 少于 2 个点没有曲线。 */
  static build(values: number[], w: number, h: number): SparkShape | undefined {
    const n = values.length;
    if (n < 2 || w <= 0 || h <= 0) {
      return undefined;
    }
    let max = 0;
    for (const v of values) {
      max = Math.max(max, v);
    }
    max = Math.max(max, 1e-3) * 1.15;
    const dx = w / (n - 1);
    const pts: SparkPoint[] = [];
    for (let i = 0; i < n; i++) {
      const p: SparkPoint = { x: i * dx, y: h - Math.max(0, values[i]) / max * h * 0.92 };
      pts.push(p);
    }
    const d: number[] = [];
    for (let i = 0; i < n - 1; i++) {
      d.push((pts[i + 1].y - pts[i].y) / dx);
    }
    const m: number[] = new Array<number>(n).fill(0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    const segs: SparkSegment[] = [];
    for (let i = 0; i < n - 1; i++) {
      const p0 = pts[i];
      const p1 = pts[i + 1];
      const s: SparkSegment = {
        c1: { x: p0.x + dx / 3, y: Math.min(h, p0.y + m[i] * dx / 3) },
        c2: { x: p1.x - dx / 3, y: Math.min(h, p1.y - m[i + 1] * dx / 3) },
        to: p1
      };
      segs.push(s);
    }
    const shape: SparkShape = { start: pts[0], segments: segs, head: pts[n - 1] };
    return shape;
  }
}

export class GlobalPick {
  static isExit(n: NodeSummary): boolean {
    return n.id >= 0 && NON_NODES.indexOf(n.protocol.toUpperCase().replace('-', '')) < 0;
  }

  /** 延迟最低的另一个节点；超时（−1）不选，未测的排最后。 */
  static best(nodes: NodeSummary[], current: NodeSummary | undefined): NodeSummary | undefined {
    let best: NodeSummary | undefined = undefined;
    let bestMs = Number.MAX_VALUE;
    for (const n of nodes) {
      if (!GlobalPick.isExit(n)) {
        continue;
      }
      if (current !== undefined && (n.id === current.id || n.name === current.name)) {
        continue;
      }
      if (n.latencyMs !== undefined && (n.latencyMs === LATENCY_TIMEOUT || n.latencyMs < 0)) {
        continue;
      }
      const ms = n.latencyMs ?? Number.MAX_VALUE - 1;
      if (best === undefined || ms < bestMs) {
        best = n;
        bestMs = ms;
      }
    }
    return best;
  }

  /** GLOBAL 组成员；没有该组（Mock / 未连接核心）时退回场景候选并集（去重）。 */
  static async candidates(engine: ZephyrEngine, scenes: Scene[]): Promise<NodeSummary[]> {
    try {
      const page = await engine.groupMembers(GLOBAL_GROUP, 0, 500);
      if (page.rows.length > 0) {
        return page.rows;
      }
    } catch (e) {
      // 没有 GLOBAL 组：走场景候选。
    }
    const seen: Set<NodeId> = new Set<NodeId>();
    const all: NodeSummary[] = [];
    for (const s of scenes) {
      if (s.source === SceneSource.SUBSCRIPTION_GROUP) {
        continue;
      }
      try {
        const c = await engine.sceneCandidates(s.id);
        for (const n of c) {
          if (!seen.has(n.id)) {
            seen.add(n.id);
            all.push(n);
          }
        }
      } catch (e) {
        // 跳过取不到候选的场景。
      }
    }
    return all;
  }
}

export interface HomeSubsView {
  rows: Subscription[];
  /** “更多 N 个订阅”的 N（0 = 不显示）。 */
  more: number;
}

export class HomeSubs {
  static view(subs: Subscription[]): HomeSubsView {
    const v: HomeSubsView = { rows: subs.slice(0, HOME_SUBS_MAX), more: Math.max(0, subs.length - HOME_SUBS_MAX) };
    return v;
  }
}

export class Failover {
  /** 撤销是否仍适用：场景还在且当前出口仍是自动切换到的那个节点。 */
  static canUndo(n: SceneFailoverNotice, scenes: Scene[]): boolean {
    if (n.switchedTo === undefined || n.previousNodeId === undefined) {
      return false;
    }
    const s = scenes.find((x: Scene) => x.id === n.sceneId);
    return s !== undefined && s.selected.name === n.switchedTo;
  }
}
