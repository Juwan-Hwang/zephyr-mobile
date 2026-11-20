/*
 * 首页场景行的“滑动换地区”槽位（原型 978–988，对照 Android HomeViewModel.prefetchSlots / SceneRow）：
 * - 每个地区一个槽：场景池里该地区最快的节点；当前出口占它所在地区的槽。
 * - 顺序：REGION_ORDER，其余按地区码；不循环，两端夹住。
 * - 每滑过 42vp 跨一个槽。
 */
import { NodeSummary, Scene, SceneSource } from '../engine/Model';

export const REGION_ORDER: string[] = ['HK', 'TW', 'JP', 'KR', 'SG', 'US', 'GB', 'DE', 'FR', 'NL', 'CA', 'AU'];
export const SCRUB_STEP_VP: number = 42;

function latencyKey(n: NodeSummary): number {
  return n.latencyMs !== undefined && n.latencyMs >= 0 ? n.latencyMs : Number.MAX_SAFE_INTEGER;
}

function orderKey(region: string): number {
  const i = REGION_ORDER.indexOf(region);
  return i < 0 ? REGION_ORDER.length : i;
}

export class SceneSlots {
  static build(scene: Scene, pool: NodeSummary[]): NodeSummary[] {
    const byRegion = new Map<string, NodeSummary>();
    const all: NodeSummary[] = pool.concat([scene.selected]);
    for (const n of all) {
      if (n.id < 0 || n.region.trim().length === 0) {
        continue;
      }
      const r = n.region.toUpperCase();
      const cur = byRegion.get(r);
      if (cur === undefined) {
        byRegion.set(r, n);
      } else if (cur.id !== scene.selected.id && (n.id === scene.selected.id || latencyKey(n) < latencyKey(cur))) {
        byRegion.set(r, n);
      }
    }
    const regions: string[] = Array.from(byRegion.keys());
    regions.sort((a: string, b: string) => {
      const d = orderKey(a) - orderKey(b);
      return d !== 0 ? d : (a < b ? -1 : a > b ? 1 : 0);
    });
    return regions.map((r: string) => byRegion.get(r) as NodeSummary);
  }

  /** 订阅分组来源的场景由订阅决定出口，不能滑；只有一个槽也不能滑。 */
  static swipeable(scene: Scene, slots: NodeSummary[]): boolean {
    return scene.source !== SceneSource.SUBSCRIPTION_GROUP && slots.length > 1;
  }

  static currentIndex(scene: Scene, slots: NodeSummary[]): number {
    const i = slots.findIndex((n: NodeSummary) => n.id === scene.selected.id);
    return i < 0 ? 0 : i;
  }

  /** 滑动 dx（vp，已按书写方向取正负）后的槽下标，两端夹住。 */
  static indexAfter(current: number, dx: number, count: number): number {
    if (count <= 0) {
      return 0;
    }
    const i = current + Math.round(dx / SCRUB_STEP_VP);
    return Math.max(0, Math.min(count - 1, i));
  }
}
