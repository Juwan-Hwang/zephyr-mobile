#!/usr/bin/env node
// contract/fixtures/*.json 结构自检：可解析、带 version（mock-v0 为生成物，带 generator）、
// cases 不为空且主键唯一。手写样本（uhd-names / import-payload）重复或错类型会让三端单测“全过但白测”。
// 用法：node tools/check-fixtures.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), '../contract/fixtures');
const errors = [];
const keyOf = { 'uhd-names-v1.json': 'name', 'import-payload-v1.json': 'id' };
const typed = {
  'uhd-names-v1.json': (c) => typeof c.name === 'string' && typeof c.uhd === 'boolean',
  // 成功例带 ok（{kind, items}），失败例带 err（错误码字符串），二者恰有其一
  'import-payload-v1.json': (c) =>
    typeof c.id === 'string' &&
    typeof c.input === 'string' &&
    ('ok' in c) !== ('err' in c) &&
    (('ok' in c && typeof c.ok?.kind === 'string' && Array.isArray(c.ok.items)) || typeof c.err === 'string'),
};

for (const f of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
  let doc;
  try {
    doc = JSON.parse(readFileSync(join(dir, f), 'utf8'));
  } catch (e) {
    errors.push(`${f}: JSON 解析失败：${e.message}`);
    continue;
  }
  if (doc.version === undefined && doc.generator === undefined) errors.push(`${f}: 缺少 version`);
  if (!Array.isArray(doc.cases)) continue;
  if (doc.cases.length === 0) errors.push(`${f}: cases 为空`);
  const key = keyOf[f];
  const seen = new Set();
  doc.cases.forEach((c, i) => {
    if (typed[f] && !typed[f](c)) errors.push(`${f}: cases[${i}] 字段类型不符：${JSON.stringify(c)}`);
    if (key) {
      if (seen.has(c[key])) errors.push(`${f}: cases[${i}] ${key} 重复：${JSON.stringify(c[key])}`);
      seen.add(c[key]);
    }
  });
  console.log(`${f}: ok${Array.isArray(doc.cases) ? `（${doc.cases.length} 例）` : ''}`);
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
