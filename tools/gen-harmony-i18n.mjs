#!/usr/bin/env node
// 由三端术语表 contract/i18n/glossary-v1.json 生成鸿蒙（ArkTS）资源：
//   tokens/generated/harmony/resources/<base|语言>/element/string.json   名称 term_<key>（key 里的 . 换成 _）
//   tokens/generated/harmony/ZTerms.ets                                   ZTerm.<camel> = $r('app.string.term_<key>')
// base 为英文；其余按语言码建限定目录（zh、ja、ar…，OHOS 资源限定词只用语言码即可匹配）。
// apps/harmony 把这些目录合并进 entry/src/main/resources 后用 $r('app.string.term_nodes') 或 ZTerm.nodes。
// 用法：node tools/gen-harmony-i18n.mjs [--check]   （--check：产物与术语表不一致则失败，不写文件）
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const check = process.argv.includes('--check');
const g = JSON.parse(readFileSync(join(root, 'contract/i18n/glossary-v1.json'), 'utf8'));
const out = join(root, 'tokens/generated/harmony');
const name = (k) => 'term_' + k.replace(/[^a-z0-9]+/gi, '_').toLowerCase();
const camel = (k) => k.replace(/[^a-z0-9]+([a-z0-9])/gi, (_, c) => c.toUpperCase());
const keys = Object.keys(g.terms);

const seen = new Map();
for (const k of keys) {
  const n = name(k);
  if (seen.has(n)) throw new Error(`术语 ${k} 与 ${seen.get(n)} 生成同名资源 ${n}`);
  seen.set(n, k);
}

const files = new Map();
for (const lang of g.locales) {
  const dir = lang === 'en' ? 'base' : lang;
  const strings = keys.map((k) => {
    const v = g.terms[k][lang];
    if (typeof v !== 'string' || !v) throw new Error(`术语 ${k} 缺 ${lang} 译名`);
    return { name: name(k), value: v };
  });
  files.set(`resources/${dir}/element/string.json`, JSON.stringify({ string: strings }, null, 2) + '\n');
}
const ets = [
  `// 自动生成：node tools/gen-harmony-i18n.mjs（源：contract/i18n/glossary-v1.json v${g.version}）。勿手改。`,
  `// 三端统一术语。ArkUI 里 Text(ZTerm.nodes)；需要字符串时用 getContext().resourceManager.getStringSync(ZTerm.nodes)。`,
  '',
  'export class ZTerm {',
  ...keys.map((k) => `  static readonly ${camel(k)}: Resource = $r('app.string.${name(k)}');`),
  '}',
  '',
].join('\n');
files.set('ZTerms.ets', ets);

let bad = 0;
for (const [rel, body] of files) {
  const p = join(out, rel);
  if (check) {
    if (!existsSync(p) || readFileSync(p, 'utf8') !== body) { console.error(`过期：tokens/generated/harmony/${rel}`); bad++; }
  } else {
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  }
}
if (bad) { console.error('请运行 node tools/gen-harmony-i18n.mjs 重新生成'); process.exit(1); }
console.log(`${check ? 'ok' : 'wrote'}: ${keys.length} 个术语 × ${g.locales.length} 种语言 → tokens/generated/harmony`);
