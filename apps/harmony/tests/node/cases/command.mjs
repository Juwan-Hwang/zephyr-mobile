// contract/fixtures/command-parse-v1.json 对拍 CommandParser（rt/ 由 vpntest.sh 生成）。
import fs from 'node:fs';
const REPO = process.env.REPO ?? new URL('../../../../../', import.meta.url).pathname;
const { CommandParser } = await import('../.out/rt/engine/CommandParser.ts');
const fx = JSON.parse(fs.readFileSync(`${REPO}/contract/fixtures/command-parse-v1.json`, 'utf8'));
let bad = 0;
for (const c of fx.cases) {
  const p = CommandParser.parse(c.input);
  const got = { service: p.service?.name ?? null, scope: p.service?.scope ?? null, region: p.region ? { name: p.region.name, code: p.region.code } : null, action: p.act ?? null,
    tokens: p.spans.map((s) => ({ start: s.start, len: s.length, kind: s.kind, text: c.input.substr(s.start, s.length) })) };
  const want = { service: c.service, scope: c.scope, region: c.region, action: c.action, tokens: c.tokens };
  if (JSON.stringify(got) !== JSON.stringify(want)) { bad++; console.log('MISMATCH', c.input, JSON.stringify(got), '!=', JSON.stringify(want)); }
}
console.log(bad ? `command FAIL ${bad}/${fx.cases.length}` : `command ok ${fx.cases.length}`);
process.exit(bad ? 1 : 0);
