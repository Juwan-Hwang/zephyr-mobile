import { describe, expect, it } from '@ohos/hypium';
import { FunnelStepValue, LedeKind, SceneSheetModel } from '../../../main/ets/app/SceneSheetModel';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { copySettings, NodeFunnel, NodeSummary, Scene, SceneSource } from '../../../main/ets/engine/Model';

/* 场景 sheet（M1-5 / U9）：候选排序与截断、导语、漏斗步骤与条宽、检测频率、来源切换收起。 */

function node(id: number, latency: number | undefined): NodeSummary {
  const n: NodeSummary = { id: id, name: 'N' + String(id), region: 'JP', protocol: 'VLESS', latencyMs: latency };
  return n;
}

function funnel(pool: number): NodeFunnel {
  const f: NodeFunnel = { sourceCount: 2, poolSize: pool, tested: 300, reachable: 120, underThreshold: 40, thresholdMs: 300 };
  return f;
}

export default function sceneSheetTest(): void {
  describe('SceneSheet', () => {
    it('pool sorted by latency, untested last, 12 shown', 0, () => {
      const list: NodeSummary[] = [node(1, undefined), node(2, 80), node(3, -1), node(4, 20)];
      for (let i = 10; i < 30; i++) {
        list.push(node(i, 100 + i));
      }
      const s = SceneSheetModel.sortByLatency(list);
      expect(s[0].id).assertEqual(4);
      expect(s[1].id).assertEqual(2);
      expect(s[s.length - 1].latencyMs === undefined || (s[s.length - 1].latencyMs as number) < 0).assertTrue();
      expect(SceneSheetModel.shownPool(s).length).assertEqual(12);
    });

    it('lede: funnel when pooled, else subscriptions + candidates', 0, () => {
      expect(SceneSheetModel.lede(true, funnel(512), 3, 9).kind).assertEqual(LedeKind.POOL);
      expect(SceneSheetModel.lede(true, funnel(512), 3, 9).pool).assertEqual(512);
      expect(SceneSheetModel.lede(false, funnel(512), 3, 9).pool).assertEqual(9);
      expect(SceneSheetModel.lede(true, funnel(0), 3, 0).kind).assertEqual(LedeKind.SOURCES);
      expect(SceneSheetModel.lede(false, undefined, 0, 9).kind).assertEqual(LedeKind.NONE);
      expect(SceneSheetModel.showFunnel(false, funnel(512))).assertFalse();
      expect(SceneSheetModel.showFunnel(true, funnel(0))).assertFalse();
    });

    it('funnel steps and log-scale bars', 0, () => {
      const steps: FunnelStepValue[] = SceneSheetModel.funnelSteps(funnel(512));
      expect(steps.length).assertEqual(4);
      expect(SceneSheetModel.funnelTop(steps)).assertEqual(512);
      expect(SceneSheetModel.barWidth(512, 512)).assertEqual(160);
      expect(SceneSheetModel.barWidth(1, 512)).assertEqual(12);
      expect(SceneSheetModel.barWidth(0, 512)).assertEqual(12);
      expect(SceneSheetModel.barWidth(5, 1)).assertEqual(160);
      expect(SceneSheetModel.barWidth(40, 512) < SceneSheetModel.barWidth(120, 512)).assertTrue();
    });

    it('retest frequency and source rules', 0, () => {
      const e = new MockEngine({ latencyScale: 0 });
      const st = copySettings(e.settings().value);
      st.latencyTtlHours = 0;
      expect(SceneSheetModel.retestHours(st)).assertEqual(24);
      st.latencyTtlHours = 6;
      expect(SceneSheetModel.retestHours(st)).assertEqual(6);
      expect(SceneSheetModel.funnelMaxAgeMs(st)).assertEqual(6 * 3600000);
      st.latencyTtlHours = 0;
      expect(SceneSheetModel.funnelMaxAgeMs(st)).assertEqual(3600000);
      const ai: Scene | undefined = e.scenes().value.find((s: Scene) => s.kind === 'ai');
      expect(ai !== undefined).assertTrue();
      if (ai !== undefined) {
        expect(SceneSheetModel.closesAfterSource(ai, SceneSource.AUTO)).assertTrue();
        expect(SceneSheetModel.closesAfterSource(ai, SceneSource.SUBSCRIPTION_GROUP)).assertFalse();
        expect(SceneSheetModel.asksOnFailure(ai)).assertTrue();
      }
    });
  });
}
