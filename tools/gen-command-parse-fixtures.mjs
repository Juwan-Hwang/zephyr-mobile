#!/usr/bin/env node
// 从原型 design/prototype/index.html 的 parse()（SVC / RGN / ACT 词表）生成指令解析样本，
// 供两端 CommandTokenizer / CommandParser 单测对齐（契约 §15.b）。
// 用法：node tools/gen-command-parse-fixtures.mjs          写入 contract/fixtures/command-parse-v1.json
//       node tools/gen-command-parse-fixtures.mjs --check  与已提交文件比对，不一致退出 1
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(join(root, 'design/prototype/index.html'), 'utf8');
const pick = (re, what) => {
  const m = html.match(re);
  if (!m) throw new Error(`原型中找不到 ${what}`);
  return m[0];
};
const src = [
  pick(/const SVC=\[[\s\S]*?\]\];/, 'SVC'),
  pick(/const RGN=\[[\s\S]*?\]\];/, 'RGN'),
  pick(/const ACT=\[[\s\S]*?\]\];/, 'ACT'),
  pick(/const SUG=\[[^\n]*\];/, 'SUG'),
  pick(/function parse\(q\)\{[\s\S]*?return \{svc,rg,act,t\};\}/, 'parse()'),
  'return {parse, SUG};',
].join('\n');
const { parse, SUG } = new Function(src)();

const KIND = { s: 'service', r: 'region', a: 'action' };
// 未收录"流媒体…"：原型对"视频|流媒体"固定 len=2，"流媒体"只会下划线"流媒"，属原型笔误；两端按实际匹配长度。
// 输入：原型建议 + 评审中提到的例子 + 每个词表的典型命中 + 边界（大小写、两字母码独立性、无命中）。
const inputs = [
  ...SUG,
  '', 'Claude 走美国', 'ChatGPT 用新加坡', 'netflix 香港', 'YouTube 4K', 'Disney+ 台湾',
  'telegram 直连', '奈飞 东京', '油管 不走代理', '谷歌AI 大阪', 'GEMINI JAPAN', 'openai tokyo',
  'github direct', '视频 英国', 'gpt 伦敦', 'claude us', 'claude plus',
  'chatgpt sg', 'disney 狮城', '电报 台北', 'tw', 'example.com', '1.1.1.1', '随便看看',
];

const cases = inputs.map((input) => {
  const r = parse(input);
  const tokens = r.t
    .slice()
    .sort((a, b) => a[0] - b[0])
    .map(([start, len, k]) => ({ start, len, kind: KIND[k], text: input.slice(start, start + len) }));
  return {
    input,
    service: r.svc ? r.svc.n : null,
    scope: r.svc ? r.svc.sc : null,
    region: r.rg ? { name: r.rg.n, code: r.rg.c } : null,
    action: r.act ?? null,
    tokens,
  };
});

const out = {
  $comment:
    '由 tools/gen-command-parse-fixtures.mjs 从原型 parse() 生成，勿手改。start/len 为 UTF-16 下标（本样本均为 BMP 字符，等同字符下标）。scope ∈ AI|视频|其他。见契约 §15.b。',
  version: 1,
  cases,
};
const text = JSON.stringify(out, null, 2) + '\n';
const file = join(root, 'contract/fixtures/command-parse-v1.json');
if (process.argv.includes('--check')) {
  let cur = '';
  try { cur = readFileSync(file, 'utf8'); } catch {}
  if (cur !== text) { console.error('command-parse-v1.json 与原型 parse() 不一致，请重新生成'); process.exit(1); }
  console.log(`ok: ${cases.length} cases`);
} else {
  writeFileSync(file, text);
  console.log(`wrote ${cases.length} cases`);
}
