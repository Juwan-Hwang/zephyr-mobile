#!/usr/bin/env node
// 校验 core-mobile 的 UniFFI 导出都写进了契约：#[uniffi::export] impl 块里的 `pub fn` 与顶层导出函数，
// 其 camelCase 名必须出现在 contract/zephyr-engine.md（构造函数 new 除外）；导出类型名同样必须出现。
// 用法：node tools/check-contract-exports.mjs
import { readFileSync, readdirSync, existsSync } from 'node:fs';
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

// 鸿蒙 napi 薄层（apps/harmony/native/core-ohos，D 维护；目录不存在时跳过）：
//  a) 每个 #[napi] 函数 / 方法要么一对一转发某个 UniFFI 导出（同 snake 名），要么其 JS 名写进契约；
//  b) 手写的 index.d.ts 必须声明每个 JS 名（导出函数、类、方法、#[napi(object)] 接口），防漂移。
const napiErrors = [];
let napiCount = 0;
const ohosDir = join(root, 'apps/harmony/native/core-ohos');
if (existsSync(join(ohosDir, 'src'))) {
  const dts = existsSync(join(ohosDir, 'index.d.ts')) ? readFileSync(join(ohosDir, 'index.d.ts'), 'utf8') : '';
  if (!dts) napiErrors.push('apps/harmony/native/core-ohos/index.d.ts 不存在');
  const inDts = (n) => new RegExp(`\\b${n}\\b`).test(dts);
  for (const f of readdirSync(join(ohosDir, 'src')).filter((f) => f.endsWith('.rs'))) {
    const src = readFileSync(join(ohosDir, 'src', f), 'utf8');
    const re = /#\[napi(?:\(([^)]*)\))?\]\s*(?:\/\/[^\n]*\n\s*|#\[[^\n]*\]\s*)*pub\s+(?:async\s+)?(fn|struct)\s+(\w+)/g;
    let m;
    while ((m = re.exec(src))) {
      const [, args = '', kind, rust] = m;
      if (/\bconstructor\b/.test(args)) continue;
      const jsName = (args.match(/js_name\s*=\s*"(\w+)"/) || [])[1] || (kind === 'struct' ? rust : camel(rust));
      napiCount++;
      if (!inDts(jsName)) napiErrors.push(`index.d.ts 缺 ${jsName}  (core-ohos/src/${f})`);
      if (kind === 'fn' && !exported.has(rust) && !new RegExp(`\\b${jsName}\\b`).test(contract))
        napiErrors.push(`napi ${jsName} 既不是 UniFFI 导出的转发，也没写进契约  (core-ohos/src/${f})`);
    }
  }
}
if (napiErrors.length) {
  console.error(`鸿蒙 napi 导出检查失败 ${napiErrors.length} 项：`);
  for (const e of napiErrors) console.error(`  ${e}`);
}
if (missing.length || missingTypes.length || napiErrors.length) {
  if (missing.length || missingTypes.length) console.error(`契约缺少 ${missing.length} 个 UniFFI 导出、${missingTypes.length} 个类型（请在 contract/zephyr-engine.md 追加说明）：`);
  for (const [n, f] of missing) console.error(`  ${camel(n)}  (core-mobile/src/${f})`);
  for (const [n, f] of missingTypes) console.error(`  type ${n}  (core-mobile/src/${f})`);
  process.exit(1);
}
console.log(`contract covers all ${exported.size} UniFFI exports and ${types.size} types` + (napiCount ? `; core-ohos ${napiCount} napi exports consistent with index.d.ts` : ''));
