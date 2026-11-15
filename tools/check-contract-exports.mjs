#!/usr/bin/env node
// 校验 core-mobile 的 UniFFI 导出都写进了契约：#[uniffi::export] impl 块里的 `pub fn` 与顶层导出函数，
// 其 camelCase 名必须出现在 contract/zephyr-engine.md（构造函数 new 除外）；导出类型名同样必须出现。
// 用法：node tools/check-contract-exports.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const srcDir = join(root, 'core-mobile/src');
const contract = readFileSync(join(root, 'contract/zephyr-engine.md'), 'utf8');
const camel = (s) => s.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());

const exported = new Map(); // name -> file
for (const f of readdirSync(srcDir).filter((f) => f.endsWith('.rs'))) {
  const src = readFileSync(join(srcDir, f), 'utf8');
  const implRe = /#\[uniffi::export\]\s*impl\s+\w+\s*\{/g;
  let m;
  while ((m = implRe.exec(src))) {
    let i = m.index + m[0].length, depth = 1;
    const start = i;
    while (depth && i < src.length) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') depth--;
      i++;
    }
    for (const fm of src.slice(start, i).matchAll(/\n {4}pub fn (\w+)/g)) exported.set(fm[1], f);
  }
  for (const fm of src.matchAll(/#\[uniffi::export\]\s*pub fn (\w+)/g)) exported.set(fm[1], f);
}

// 类型：Record / Enum / Object / Error 与回调接口
const types = new Map();
for (const f of readdirSync(srcDir).filter((f) => f.endsWith('.rs'))) {
  const src = readFileSync(join(srcDir, f), 'utf8');
  for (const tm of src.matchAll(/uniffi::(?:Record|Enum|Object|Error)\b[^\n]*\n(?:\s*(?:#\[[^\n]*|\/\/\/[^\n]*)\n)*\s*pub (?:struct|enum) (\w+)/g)) types.set(tm[1], f);
  for (const tm of src.matchAll(/#\[uniffi::export\(callback_interface\)\]\s*pub trait (\w+)/g)) types.set(tm[1], f);
}
const missingTypes = [...types].filter(([n]) => !new RegExp(`\\b${n}\\b`).test(contract));

const missing = [...exported].filter(([n]) => n !== 'new' && !new RegExp(`\\b${camel(n)}\\b`).test(contract));
if (missing.length || missingTypes.length) {
  console.error(`契约缺少 ${missing.length} 个 UniFFI 导出、${missingTypes.length} 个类型（请在 contract/zephyr-engine.md 追加说明）：`);
  for (const [n, f] of missing) console.error(`  ${camel(n)}  (core-mobile/src/${f})`);
  for (const [n, f] of missingTypes) console.error(`  type ${n}  (core-mobile/src/${f})`);
  process.exit(1);
}
console.log(`contract covers all ${exported.size} UniFFI exports and ${types.size} types`);
