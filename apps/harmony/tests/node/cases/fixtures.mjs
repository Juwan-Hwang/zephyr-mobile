// contract/fixtures 校验：mock-v0（节点 / 查询 / 规则）、import-payload-v1、uhd-names-v1，外加 MockEngine 冒烟。
import fs from 'node:fs';
const REPO = process.env.REPO ?? new URL('../../../../../', import.meta.url).pathname;
const read = (p) => JSON.parse(fs.readFileSync(`${REPO}/contract/fixtures/${p}`, 'utf8'));
const fx = read('mock-v0.json');
const { MockCatalog } = await import('../.out/rt/engine/mock/MockCatalog.ts');
const { NodeQuery } = await import('../.out/rt/engine/mock/NodeQuery.ts');
const { MockRules } = await import('../.out/rt/engine/mock/MockRules.ts');
const { ImportPayloads, ImportPayloadError } = await import('../.out/rt/engine/mock/ImportPayloads.ts');
const { MockEngine, isUhdName } = await import('../.out/rt/engine/MockEngine.ts');

let bad = 0;
const counts = {};
const eq = (a, b, m) => {
  const k = m.split(' ')[0];
  counts[k] = (counts[k] ?? 0) + 1;
  if (JSON.stringify(a) !== JSON.stringify(b)) { bad++; if (bad < 20) console.log('MISMATCH', m, JSON.stringify(a), '!=', JSON.stringify(b)); }
};

// ── mock-v0: catalogue
eq(MockCatalog.total(), fx.total, 'total');
eq(MockCatalog.REGIONS.map((g) => [g.code, g.name, g.count, g.cities, g.baseLatency, g.carriers]), fx.regions.map((r) => Array.isArray(r) ? r : [r.code, r.name, r.count, r.cities, r.baseLatency, r.carriers]), 'regions');
eq(MockCatalog.TAGS, fx.tags, 'tags');
eq(MockCatalog.PROTOCOLS, fx.protocols, 'protocols');
for (const n of fx.nodes) {
  const s = MockCatalog.summary(n.region, n.index);
  eq(MockCatalog.idOf(n.region, n.index), n.id, 'node-id ' + n.id);
  eq([s.name, s.tag, s.protocol, s.carrier, s.latencyMs ?? null], [n.name, n.tag, n.protocol, n.carrier, n.cachedLatency], 'node ' + n.id);
  eq(MockCatalog.hsh(n.region, n.index), n.hash, 'hash ' + n.id);
}
// ── mock-v0: queries
for (const q of fx.queries) {
  const r = NodeQuery.build(q.query);
  eq(r.total, q.total, 'query-total ' + q.query);
  eq(r.sections().map((s) => ({ region: s.region, count: s.count })), q.sections.map((s) => ({ region: s.region, count: s.count })), 'query-sections ' + q.query);
  const rows = [];
  for (const g of r.groups) {
    rows.push({ header: MockCatalog.REGIONS[g.region].code });
    for (let k = 0; k < g.count && rows.length < q.firstRows.length; k++) {
      const j = r.indexInRegion(g, k);
      rows.push({ id: MockCatalog.idOf(g.region, j), name: MockCatalog.nodeName(g.region, j) });
    }
    if (rows.length >= q.firstRows.length) break;
  }
  eq(rows, q.firstRows.map((x) => (x.header ? { header: x.header } : { id: x.id, name: x.name })), 'query-rows ' + q.query);
}
// ── mock-v0: rules
const KIND = { override: '覆写', subscription: '订阅', domain: '域名', ip: 'IP' };
eq(MockRules.LAYERS.map((l) => ({ index: l.index, kind: KIND[l.kind], name: l.name, count: l.count, note: l.note })), fx.rules.layers, 'rules-layers');
eq(MockRules.total(), fx.rules.total, 'rules-total');
for (const t of fx.rules.tests) {
  const q = MockRules.normalise(t.input);
  const h = MockRules.match(q);
  const got = h ? { layerIndex: h.layer, rule: h.rule, ruleNo: h.ruleNo, policy: h.policy } : { layerIndex: null, rule: 'MATCH', ruleNo: null, policy: 'O' };
  eq(got, { layerIndex: t.layerIndex, rule: t.rule, ruleNo: t.ruleNo, policy: t.policy }, 'rule ' + t.input);
}
// ── import-payload-v1
for (const c of read('import-payload-v1.json').cases) {
  let got;
  try {
    const p = ImportPayloads.parse(c.input);
    got = { ok: { kind: p.kind, items: p.items.map((i) => ({ name: i.name ?? null, url: i.url, autoUpdateHours: i.autoUpdateHours ?? null })) } };
  } catch (e) {
    if (!(e instanceof ImportPayloadError)) throw e;
    got = { err: e.category };
  }
  eq(got, c.ok !== undefined ? { ok: c.ok } : { err: c.err }, 'import ' + c.id);
}
// ── uhd-names-v1
for (const c of read('uhd-names-v1.json').cases) eq(isUhdName(c.name), c.uhd, 'uhd ' + c.name);

// ── MockEngine 冒烟（latencyScale 0）
const e = new MockEngine({ latencyScale: 0, clock: () => 1_700_000_000_000 });
const idx = await e.nodeIndex();
eq(idx.total, fx.total, 'engine-index');
for (const q of fx.queries) {
  const r = await e.queryNodes(q.query);
  eq(r.total, q.total, 'engine-query ' + q.query);
  const ids = q.firstRows.filter((x) => !x.header).map((x) => x.id);
  const page = await e.nodeRows(r.token, 0, ids.length);
  eq(page.rows.map((x) => x.id), ids, 'engine-rows ' + q.query);
}
for (const t of fx.rules.tests) {
  const tr = await e.testRule(t.input);
  eq([tr.layerIndex ?? null, tr.rule, tr.ruleNo ?? null], [t.layerIndex, t.rule, t.ruleNo], 'engine-rule ' + t.input);
}
const states = [];
e.connectionState().subscribe((s) => states.push(s.status));
await e.connect();
eq(states, ['disconnected', 'connecting', 'connected'], 'engine-connect');
const sub = await e.importSubscription('url', 'zephyr://import?url=https%3A%2F%2Fsub.example.com%2Fa&name=Test');
eq([sub.name, (await e.subscriptionsSummary()).count], ['Test', 215], 'engine-import');
let threw = '';
try { await e.importSubscription('url', 'hello'); } catch (x) { threw = x.code; }
eq(threw, 'subscription_invalid', 'engine-import-invalid');
const lat = new Promise((res) => { const s = e.latencyUpdates().subscribe((u) => { s.cancel(); res(u); }); });
await e.testLatency([MockCatalog.idOf(0, 0)]);
eq((await lat)[0].latencyMs, MockCatalog.testedLatency(0, 0), 'engine-latency');
const ch = await e.previewSceneChange('ai', 9000000005);
eq([ch.toRegion, ch.toIp, ch.affectedApps, ch.unchangedApps], ['JP', '203.0.113.61', ['GPT', 'Gemini'], ['Claude']], 'engine-scene');
const u = await e.usageToday();
eq([u.hourly.length, u.hourly.reduce((a, b) => a + b, 0)], [24, 1_800_000_000], 'engine-usage');
eq((await e.ruleStats()).total, 103606731, 'engine-rulestats');
eq((await e.commandSuggestions('')).length, 5, 'engine-commands');
eq((await e.commandSuggestions('日本')).some((c) => c.kind === 'open_node_query'), true, 'engine-commands-jp');
await e.disconnect();

console.log(Object.entries(counts).map(([k, v]) => `${k}=${v}`).join(' '));
// ── command-parse-v1（§15.b）
{
  const { CommandParser } = await import('../.out/rt/engine/CommandParser.ts');
  for (const c of read('command-parse-v1.json').cases) {
    const p = CommandParser.parse(c.input);
    eq({ service: p.service?.name ?? null, scope: p.service?.scope ?? null, region: p.region ? { name: p.region.name, code: p.region.code } : null, action: p.act ?? null,
      tokens: p.spans.map((s) => ({ start: s.start, len: s.length, kind: s.kind, text: c.input.substr(s.start, s.length) })) },
    { service: c.service, scope: c.scope, region: c.region, action: c.action, tokens: c.tokens }, 'command ' + c.input);
  }
}

console.log(bad ? `FAIL ${bad}` : `OK nodes=${fx.nodes.length} queries=${fx.queries.length} rules=${fx.rules.tests.length}`);
process.exit(bad ? 1 : 0);
