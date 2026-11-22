import { describe, expect, it } from '@ohos/hypium';
import { GlobalPick, HOME_SUBS_MAX, HomeSubs, MINI_FUNNEL_GAP, MINI_FUNNEL_WIDTH, MiniFunnelGeom, SparkGeometry,
  SparkRing, SparkShape } from '../../../main/ets/app/HomeModel';
import { NodeFunnel, NodeSummary, Subscription } from '../../../main/ets/engine/Model';
import { CARD_SCENE_ROWS, CardScene, CardSnapshot, CardSnapshots } from '../../../main/ets/widget/CardSnapshot';

/* M1-6 首页 + M1-19 服务卡片纯逻辑（与 tests/node/model/home.mjs、cardsnap.mjs 对应）。 */

function node(id: number, name: string, ms: number | undefined, protocol: string): NodeSummary {
  const n: NodeSummary = { id: id, name: name, region: 'JP', protocol: protocol, latencyMs: ms };
  return n;
}

function sub(id: string): Subscription {
  const s: Subscription = { id: id, name: id, nodeCount: 1, autoUpdateHours: 24 };
  return s;
}

function funnel(pool: number, tested: number, reachable: number, under: number): NodeFunnel {
  const f: NodeFunnel = { sourceCount: 1, poolSize: pool, tested: tested, reachable: reachable,
    underThreshold: under, thresholdMs: 200 };
  return f;
}

export default function homeTest(): void {
  describe('Home logic', () => {
    it('spark ring caps and clamps', 0, () => {
      const ring = new SparkRing(4);
      ring.push(1);
      ring.push(-5);
      ring.push(3);
      ring.push(4);
      const v = ring.push(5);
      expect(v.length).assertEqual(4);
      expect(v[0]).assertEqual(0);
      expect(v[3]).assertEqual(5);
      ring.clear();
      expect(ring.values().length).assertEqual(0);
    });

    it('spark geometry endpoints stay in box', 0, () => {
      expect(SparkGeometry.build([1], 100, 20) === undefined).assertTrue();
      const g: SparkShape | undefined = SparkGeometry.build([0, 5, 10, 5, 0], 100, 20);
      expect(g !== undefined).assertTrue();
      if (g !== undefined) {
        expect(g.segments.length).assertEqual(4);
        expect(g.start.x).assertEqual(0);
        expect(g.head.x).assertEqual(100);
      }
    });

    it('global pick lowest latency exit', 0, () => {
      const nodes: NodeSummary[] = [node(1, 'a', 80, 'vmess'), node(2, 'b', 30, 'vmess'), node(3, 'c', -1, 'vmess'),
        node(4, 'd', undefined, 'vmess'), node(-1, 'DIRECT', 1, 'Direct'), node(5, 'sel', 5, 'Selector')];
      expect(GlobalPick.best(nodes, undefined)?.name).assertEqual('b');
      expect(GlobalPick.best(nodes, nodes[1])?.name).assertEqual('a');
      expect(GlobalPick.best([nodes[2], nodes[3]], undefined)?.name).assertEqual('d');
      expect(GlobalPick.best([node(5, 'u', 5, 'URL-Test')], undefined) === undefined).assertTrue();
    });

    it('home subs summary', 0, () => {
      const subs: Subscription[] = [sub('0'), sub('1'), sub('2'), sub('3'), sub('4')];
      const v = HomeSubs.view(subs);
      expect(v.rows.length).assertEqual(HOME_SUBS_MAX);
      expect(v.more).assertEqual(2);
      expect(HomeSubs.view(subs.slice(0, 2)).more).assertEqual(0);
    });

    it('mini funnel widths shrink and fill', 0, () => {
      const w = MiniFunnelGeom.widths(funnel(10000000, 5000, 300, 9));
      expect(w.length).assertEqual(4);
      expect(w[0] > w[1] && w[1] > w[2] && w[2] > w[3] && w[3] >= 2).assertTrue();
      const sum = w.reduce((a: number, b: number) => a + b, 0) + 3 * MINI_FUNNEL_GAP;
      expect(Math.abs(sum - MINI_FUNNEL_WIDTH) < 0.000001).assertTrue();
      expect(MiniFunnelGeom.drawable(undefined)).assertFalse();
      expect(MiniFunnelGeom.drawable(funnel(0, 0, 0, 0))).assertFalse();
      expect(MiniFunnelGeom.drawable(funnel(3, 0, 0, 0))).assertTrue();
    });
  });

  describe('Service card snapshot', () => {
    it('roundtrip caps scenes, bad file falls back', 0, () => {
      const s = new CardSnapshot();
      s.on = true;
      s.title = 'on';
      for (let i = 0; i < 5; i++) {
        const c = new CardScene();
        c.name = 's' + i;
        s.scenes.push(c);
      }
      const back = CardSnapshots.decode(CardSnapshots.encode(s));
      expect(back.on).assertTrue();
      expect(back.scenes.length).assertEqual(CARD_SCENE_ROWS);
      expect(CardSnapshots.decode('{bad').on).assertFalse();
    });

    it('today resets after midnight', 0, () => {
      const s = new CardSnapshot();
      s.today = 'T 1.2 GB';
      s.todayZero = 'T 0 B';
      s.day = CardSnapshots.dayKey(Date.UTC(2026, 10, 22, 4));
      expect(CardSnapshots.forDisplay(s, Date.UTC(2026, 10, 22, 5)).today).assertEqual('T 1.2 GB');
      expect(CardSnapshots.forDisplay(s, Date.UTC(2026, 10, 24, 5)).today).assertEqual('T 0 B');
      expect(s.today).assertEqual('T 1.2 GB');
    });

    it('form ids keep their size', 0, () => {
      let ids: string[] = CardSnapshots.withId([], '1', false);
      ids = CardSnapshots.withId(ids, '2', true);
      ids = CardSnapshots.withId(ids, '1', true);
      expect(ids.length).assertEqual(2);
      expect(CardSnapshots.wideOf(ids, '1')).assertTrue();
      expect(CardSnapshots.wideOf(ids, '3')).assertFalse();
      ids = CardSnapshots.withoutId(ids, '1');
      expect(CardSnapshots.idOf(ids[0])).assertEqual('2');
    });
  });
}
