import { describe, expect, it } from '@ohos/hypium';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { MockCatalog } from '../../../main/ets/engine/mock/MockCatalog';
import { ZephyrError } from '../../../main/ets/engine/ZephyrEngine';
import {
  CommandKind, CommandSuggestion, ConnectionState, ExitChange, ImportSource, LatencyUpdate, NodePage, NodeQueryResult,
  NodeSummary, RuleTrace, Subscription, UsageSummary
} from '../../../main/ets/engine/Model';
import { Subscription as StreamSubscription } from '../../../main/ets/engine/Stream';
import { MOCK_V0 } from './fixtures/Fixtures';
import { FxQuery, FxRow, FxRuleTest, MockV0 } from './FixtureTypes';

/* MockEngine 冒烟（latencyScale 0、固定时钟），与 ets-check/test.mjs 的 engine-* 断言一致。 */

const FIXED_NOW: number = 1700000000000;

function newEngine(): MockEngine {
  return new MockEngine({ latencyScale: 0, clock: (): number => FIXED_NOW });
}

export default function mockEngineTest(): void {
  const fx: MockV0 = JSON.parse(MOCK_V0) as MockV0;

  describe('MockEngine', () => {
    it('nodeIndex / queryNodes / nodeRows', 0, async () => {
      const e = newEngine();
      expect((await e.nodeIndex()).total).assertEqual(fx.total);
      for (const q of fx.queries) {
        const fq: FxQuery = q;
        const r: NodeQueryResult = await e.queryNodes(fq.query);
        expect(r.total).assertEqual(fq.total);
        const ids: number[] = fq.firstRows.filter((x: FxRow) => x.header === undefined).map((x: FxRow) => x.id ?? -1);
        const page: NodePage = await e.nodeRows(r.token, 0, ids.length);
        expect(JSON.stringify(page.rows.map((x: NodeSummary) => x.id))).assertEqual(JSON.stringify(ids));
      }
    });

    it('testRule', 0, async () => {
      const e = newEngine();
      for (const t of fx.rules.tests) {
        const ft: FxRuleTest = t;
        const tr: RuleTrace = await e.testRule(ft.input);
        expect(JSON.stringify([tr.layerIndex ?? null, tr.rule, tr.ruleNo ?? null]))
          .assertEqual(JSON.stringify([ft.layerIndex, ft.rule, ft.ruleNo]));
      }
    });

    it('connect / import / latency / scene / usage / rules / commands', 0, async () => {
      const e = newEngine();
      const states: string[] = [];
      const sub: StreamSubscription = e.connectionState().subscribe((s: ConnectionState) => {
        states.push(s.status as string);
      });
      await e.connect();
      sub.cancel();
      expect(JSON.stringify(states)).assertEqual(JSON.stringify(['disconnected', 'connecting', 'connected']));

      const imported: Subscription =
        await e.importSubscription(ImportSource.URL, 'zephyr://import?url=https%3A%2F%2Fsub.example.com%2Fa&name=Test');
      expect(imported.name).assertEqual('Test');
      expect((await e.subscriptionsSummary()).count).assertEqual(215);
      let code = '';
      try {
        await e.importSubscription(ImportSource.URL, 'hello');
      } catch (x) {
        code = x instanceof ZephyrError ? (x.code as string) : 'other';
      }
      expect(code).assertEqual('subscription_invalid');

      let resolveFirst: (u: LatencyUpdate[]) => void = (u: LatencyUpdate[]): void => {};
      const firstUpdate: Promise<LatencyUpdate[]> = new Promise<LatencyUpdate[]>((resolve: (u: LatencyUpdate[]) => void) => {
        resolveFirst = resolve;
      });
      const ls: StreamSubscription = e.latencyUpdates().subscribe((u: LatencyUpdate[]) => resolveFirst(u));
      await e.testLatency([MockCatalog.idOf(0, 0)]);
      const first: LatencyUpdate[] = await firstUpdate;
      ls.cancel();
      expect(first.length > 0).assertTrue();
      expect(first[0].latencyMs).assertEqual(MockCatalog.testedLatency(0, 0));

      const ch: ExitChange = await e.previewSceneChange('ai', 9000000005);
      expect(JSON.stringify([ch.toRegion, ch.toIp, ch.affectedApps, ch.unchangedApps]))
        .assertEqual(JSON.stringify(['JP', '203.0.113.61', ['GPT', 'Gemini'], ['Claude']]));

      const u: UsageSummary = await e.usageToday();
      expect(u.hourly.length).assertEqual(24);
      expect(u.hourly.reduce((a: number, b: number) => a + b, 0)).assertEqual(1800000000);
      expect((await e.ruleStats()).total).assertEqual(103606731);
      expect((await e.commandSuggestions('')).length).assertEqual(5);
      const jp: CommandSuggestion[] = await e.commandSuggestions('日本');
      expect(jp.some((c: CommandSuggestion) => c.kind === CommandKind.OPEN_NODE_QUERY)).assertTrue();
      await e.disconnect();
    });
  });
}
