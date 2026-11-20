import { describe, expect, it } from '@ohos/hypium';
import { MockCatalog, Region } from '../../../main/ets/engine/mock/MockCatalog';
import { NodeQuery, QueryGroup } from '../../../main/ets/engine/mock/NodeQuery';
import { MockRules, RuleHit } from '../../../main/ets/engine/mock/MockRules';
import { ImportPayloadError, ImportPayloads } from '../../../main/ets/engine/mock/ImportPayloads';
import { isUhdName } from '../../../main/ets/engine/MockEngine';
import { ImportItem, ImportPayload, NodeSummary, RegionSection, RuleLayer } from '../../../main/ets/engine/Model';
import { IMPORT_PAYLOAD_V1, MOCK_V0, UHD_NAMES_V1 } from './fixtures/Fixtures';
import {
  FxImportCase, FxImportItem, FxLayer, FxNode, FxQuery, FxRegion, FxRow, FxRuleTest, FxSection, FxUhdCase,
  ImportPayloadV1, MockV0, UhdNamesV1
} from './FixtureTypes';

/*
 * contract/fixtures 对拍（与 /workspace 外的 node 检查 ets-check/test.mjs 同一组断言）：
 * mock-v0（目录、查询、规则）、import-payload-v1、uhd-names-v1。command-parse-v1 待指令解析移植后加入。
 */

const KIND_ZH: Map<string, string> = new Map<string, string>([
  ['override', '覆写'], ['subscription', '订阅'], ['domain', '域名'], ['ip', 'IP']
]);

function same(a: Object | null | undefined, b: Object | null | undefined, what: string): void {
  const x = JSON.stringify(a);
  const y = JSON.stringify(b);
  if (x !== y) {
    console.error('MISMATCH ' + what + ' ' + x + ' != ' + y);
  }
  expect(x).assertEqual(y);
}

function rowOf(r: FxRow): FxRow {
  if (r.header !== undefined) {
    const h: FxRow = { header: r.header };
    return h;
  }
  const n: FxRow = { id: r.id, name: r.name };
  return n;
}

export default function mockFixturesTest(): void {
  const fx: MockV0 = JSON.parse(MOCK_V0) as MockV0;

  describe('mock-v0 catalogue', () => {
    it('total, regions, tags, protocols', 0, () => {
      expect(MockCatalog.total()).assertEqual(fx.total);
      same(MockCatalog.REGIONS.map((g: Region) => [g.code, g.name, g.count, g.cities, g.baseLatency, g.carriers]),
        fx.regions.map((r: FxRegion) => [r.code, r.name, r.count, r.cities, r.baseLatency, r.carriers]), 'regions');
      same(MockCatalog.TAGS, fx.tags, 'tags');
      same(MockCatalog.PROTOCOLS, fx.protocols, 'protocols');
    });
    it('nodes: id, summary, hash', 0, () => {
      fx.nodes.forEach((n: FxNode) => {
        const s: NodeSummary = MockCatalog.summary(n.region, n.index);
        expect(MockCatalog.idOf(n.region, n.index)).assertEqual(n.id);
        same([s.name, s.tag, s.protocol, s.carrier, s.latencyMs ?? null],
          [n.name, n.tag, n.protocol, n.carrier, n.cachedLatency], 'node ' + n.id);
        expect(MockCatalog.hsh(n.region, n.index)).assertEqual(n.hash);
      });
    });
  });

  describe('mock-v0 queries', () => {
    it('total, sections, first rows', 0, () => {
      fx.queries.forEach((q: FxQuery) => {
        const r: NodeQuery = NodeQuery.build(q.query);
        expect(r.total).assertEqual(q.total);
        same(r.sections().map((s: RegionSection) => [s.region, s.count]),
          q.sections.map((s: FxSection) => [s.region, s.count]), 'sections ' + q.query);
        const rows: FxRow[] = [];
        for (const g of r.groups) {
          const header: FxRow = { header: MockCatalog.REGIONS[g.region].code };
          rows.push(header);
          for (let k = 0; k < g.count && rows.length < q.firstRows.length; k++) {
            const j = r.indexInRegion(g, k);
            const row: FxRow = { id: MockCatalog.idOf(g.region, j), name: MockCatalog.nodeName(g.region, j) };
            rows.push(row);
          }
          if (rows.length >= q.firstRows.length) {
            break;
          }
        }
        same(rows, q.firstRows.map((x: FxRow) => rowOf(x)), 'rows ' + q.query);
      });
    });
  });

  describe('mock-v0 rules', () => {
    it('layers and total', 0, () => {
      same(MockRules.LAYERS.map((l: RuleLayer) => [l.index, KIND_ZH.get(l.kind as string) ?? '', l.name, l.count, l.note]),
        fx.rules.layers.map((l: FxLayer) => [l.index, l.kind, l.name, l.count, l.note]), 'layers');
      expect(MockRules.total()).assertEqual(fx.rules.total);
    });
    it('rule tests', 0, () => {
      fx.rules.tests.forEach((t: FxRuleTest) => {
        const h: RuleHit | undefined = MockRules.match(MockRules.normalise(t.input));
        const got = h !== undefined ? [h.layer, h.rule, h.ruleNo, h.policy] : [null, 'MATCH', null, 'O'];
        same(got, [t.layerIndex, t.rule, t.ruleNo, t.policy], 'rule ' + t.input);
      });
    });
  });

  describe('import-payload-v1', () => {
    it('cases', 0, () => {
      const cases: ImportPayloadV1 = JSON.parse(IMPORT_PAYLOAD_V1) as ImportPayloadV1;
      cases.cases.forEach((c: FxImportCase) => {
        let got = '';
        try {
          const p: ImportPayload = ImportPayloads.parse(c.input);
          got = 'ok ' + JSON.stringify([p.kind as string,
            p.items.map((i: ImportItem) => [i.name ?? null, i.url, i.autoUpdateHours ?? null])]);
        } catch (e) {
          got = e instanceof ImportPayloadError ? 'err ' + (e.category as string) : 'throw ' + String(e);
        }
        const want = c.ok !== undefined
          ? 'ok ' + JSON.stringify([c.ok.kind, c.ok.items.map((i: FxImportItem) => [i.name, i.url, i.autoUpdateHours])])
          : 'err ' + (c.err ?? '');
        same(got, want, 'import ' + c.id);
      });
    });
  });

  describe('uhd-names-v1', () => {
    it('cases', 0, () => {
      const u: UhdNamesV1 = JSON.parse(UHD_NAMES_V1) as UhdNamesV1;
      u.cases.forEach((c: FxUhdCase) => {
        expect(isUhdName(c.name)).assertEqual(c.uhd);
      });
    });
  });
}
