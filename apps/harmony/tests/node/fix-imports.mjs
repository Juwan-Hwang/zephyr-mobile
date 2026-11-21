// node 的 TS 变换不做 import 省略：给只在类型位置用的名字（interface / type 别名）加 `type` 修饰。
import fs from 'node:fs';
import path from 'node:path';
const files = [];
const walk = (d) => { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); fs.statSync(p).isDirectory() ? walk(p) : p.endsWith('.ts') && files.push(p); } };
walk(process.argv[2] ?? 'rt');
const types = new Set();
for (const f of files) for (const m of fs.readFileSync(f, 'utf8').matchAll(/export\s+(?:interface|type)\s+(\w+)/g)) types.add(m[1]);
for (const f of files) {
  const s = fs.readFileSync(f, 'utf8').replace(/import\s*\{([^}]*)\}\s*from/g, (all, names) =>
    'import {' + names.split(',').map((n) => { const t = n.trim(); return t && types.has(t) ? n.replace(t, 'type ' + t) : n; }).join(',') + '} from');
  fs.writeFileSync(f, s);
}
