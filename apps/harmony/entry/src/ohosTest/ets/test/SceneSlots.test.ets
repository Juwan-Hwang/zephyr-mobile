import { describe, expect, it } from '@ohos/hypium';
import { SceneSlots } from '../../../main/ets/app/SceneSlots';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { NodeSummary, Scene, SceneSource } from '../../../main/ets/engine/Model';

/* 首页场景行滑动槽位（U5）：每地区一个、当前出口占其地区槽、REGION_ORDER 排序、两端夹住。 */

function node(id: number, region: string, latency: number | undefined): NodeSummary {
  const n: NodeSummary = { id: id, name: region + '-' + String(id), region: region, protocol: 'VLESS', latencyMs: latency };
  return n;
}

export default function sceneSlotsTest(): void {
  describe('SceneSlots', () => {
    it('one slot per region, current keeps its slot, ordered', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      const scene: Scene = e.scenes().value[0];
      const cur = scene.selected;
      const pool: NodeSummary[] = [node(1, 'US', 150), node(2, 'US', 90), node(3, 'JP', 60), node(4, 'HK', 30),
        node(5, cur.region, 1), node(6, 'ZZ', 10), node(-1, 'JP', 1), node(7, '', 1)];
      const slots = SceneSlots.build(scene, pool);
      const regions = slots.map((n: NodeSummary) => n.region.toUpperCase());
      expect(new Set<string>(regions).size).assertEqual(regions.length);
      expect(slots.some((n: NodeSummary) => n.id === cur.id)).assertTrue();
      expect(slots.some((n: NodeSummary) => n.id === 5)).assertFalse();
      expect(regions.indexOf('HK') < regions.indexOf('JP')).assertTrue();
      expect(regions.indexOf('JP') < regions.indexOf('US')).assertTrue();
      expect(regions[regions.length - 1]).assertEqual('ZZ');
      if (cur.region.toUpperCase() !== 'US') {
        expect(slots.find((n: NodeSummary) => n.region === 'US')?.id).assertEqual(2);
      }
    });

    it('scrub index: 42vp per slot, clamped', 0, () => {
      expect(SceneSlots.indexAfter(2, 0, 5)).assertEqual(2);
      expect(SceneSlots.indexAfter(2, 42, 5)).assertEqual(3);
      expect(SceneSlots.indexAfter(2, -84, 5)).assertEqual(0);
      expect(SceneSlots.indexAfter(2, 1000, 5)).assertEqual(4);
      expect(SceneSlots.indexAfter(2, -1000, 5)).assertEqual(0);
    });

    it('subscription-group scenes and single slots do not swipe', 0, () => {
      const e = new MockEngine({ latencyScale: 0 });
      const scene: Scene = e.scenes().value[0];
      const two: NodeSummary[] = [node(1, 'HK', 1), node(2, 'JP', 1)];
      expect(SceneSlots.swipeable(scene, two) === (scene.source !== SceneSource.SUBSCRIPTION_GROUP)).assertTrue();
      expect(SceneSlots.swipeable(scene, [node(1, 'HK', 1)])).assertFalse();
    });

    it('mock pool gives the AI scene several regions', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      const scene: Scene = e.scenes().value[0];
      const slots = SceneSlots.build(scene, await e.sceneCandidates(scene.id));
      expect(slots.length > 1).assertTrue();
      expect(SceneSlots.currentIndex(scene, slots) >= 0).assertTrue();
    });
  });
}
