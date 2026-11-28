import { describe, expect, it } from '@ohos/hypium';
import { CommandPlan, CommandPlanKind, CommandPlanner } from '../../../main/ets/app/CommandPlanner';
import { TraceChoice, TraceModel } from '../../../main/ets/app/TraceModel';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { ConnectionTrace, NodeFilterPreview, RuleTrace, Scene, TraceTarget } from '../../../main/ets/engine/Model';

/* 指令 4K 卡（§15.h）与连接轨迹（M1-8 最小版）：mock 没有 4K 节点 → 不可用；覆写选项 / 下标 / 回退。 */

export default function traceTest(): void {
  describe('CommandUhdAndTrace', () => {
    it('uhd: mock pool has no 4K node → unavailable, set throws', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      const pv: NodeFilterPreview = await e.previewSceneNodeFilter('video', 'uhd');
      expect(pv.poolMatching).assertEqual(0);
      const p: CommandPlan | undefined = await new CommandPlanner(e).planText('视频只用 4K 节点');
      expect(p !== undefined && p.kind === CommandPlanKind.UHD && p.unavailable && !p.applicable).assertTrue();
      let code = '';
      try {
        await e.setSceneNodeFilter('video', 'uhd');
      } catch (x) {
        code = (x as Error).message;
      }
      expect(code.length > 0).assertTrue();
      await e.setSceneNodeFilter('video', undefined);
      expect(e.scenes().value.find((s: Scene) => s.id === 'video')?.nodeFilter === undefined).assertTrue();
    });

    it('trace: override options and round trip', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      const t: ConnectionTrace = await e.connectionTrace('github.com');
      const others = TraceModel.otherScenes(e.scenes().value, t.scene);
      expect(others.length).assertEqual(2);
      const c: TraceChoice = TraceModel.choiceAt(1, others);
      expect(c.target).assertEqual(TraceTarget.DIRECT);
      await e.overrideHost(t.host, c.target, c.sceneId, true);
      const t2 = await e.connectionTrace('github.com');
      expect(TraceModel.selectedIndex(t2.override, others)).assertEqual(1);
      const u = TraceModel.undoChoice(t.override);
      await e.overrideHost(t.host, u.target, u.sceneId, u.persistent);
      expect((await e.connectionTrace('github.com')).override === undefined).assertTrue();
    });

    it('trace: unknown host falls back to rule test', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      const r: RuleTrace = await e.testRule('chat.openai.com');
      const f = TraceModel.fromRuleTrace(r);
      expect(f.host).assertEqual(r.input);
      expect(f.connections).assertEqual(0);
      expect(TraceModel.ruleText('DOMAIN-SUFFIX,a.b')).assertEqual('DOMAIN-SUFFIX, a.b');
    });
  });
}
