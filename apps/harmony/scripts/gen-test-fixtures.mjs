#!/usr/bin/env node
// 把 contract/fixtures/*.json 原样嵌进 ohosTest：entry/src/ohosTest/ets/test/fixtures/Fixtures.ets（每个文件一个字符串常量）。
// 测试 HAP 在设备上读不到仓库文件，嵌入比 rawfile + 模块上下文更稳。输出禁止手改。
// 用法：node apps/harmony/scripts/gen-test-fixtures.mjs [--check]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const app = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.resolve(app, '../..');
const src = path.join(root, 'contract/fixtures');
const out = path.join(app, 'entry/src/ohosTest/ets/test/fixtures/Fixtures.ets');
const constName = (f) => f.replace(/\.json$/, '').replace(/[^a-z0-9]+/gi, '_').toUpperCase();

const files = fs.readdirSync(src).filter((f) => f.endsWith('.json')).sort();
const body = [
  '// 自动生成：node apps/harmony/scripts/gen-test-fixtures.mjs（源：contract/fixtures/*.json）。勿手改。',
  '',
  ...files.map((f) => {
    const text = JSON.stringify(JSON.parse(fs.readFileSync(path.join(src, f), 'utf8')));
    return `/** contract/fixtures/${f} */\nexport const ${constName(f)}: string = ${JSON.stringify(text)};\n`;
  }),
].join('\n');

if (process.argv.includes('--check')) {
  if (!fs.existsSync(out) || fs.readFileSync(out, 'utf8') !== body) {
    console.error('过期：' + path.relative(root, out) + '（运行 node apps/harmony/scripts/gen-test-fixtures.mjs）');
    process.exit(1);
  }
  console.log('ok: ' + files.length + ' 个 fixtures');
} else {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, body);
  console.log('wrote ' + path.relative(root, out) + '（' + files.length + ' 个）');
}
