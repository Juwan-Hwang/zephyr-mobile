#!/usr/bin/env node
// 鸿蒙端文案合并（角色 D）。三个来源，合成 entry/src/main/resources/<限定词>/element/{string,plural,strarray}.json：
//   1. 术语：A 的官方产物 tokens/generated/harmony/resources/<base|语言>/element/string.json（tools/gen-harmony-i18n.mjs，
//      名称 term_*），原样并入；ZTerms.ets 拷到 entry/src/main/ets/generated/ZTerms.ets。代码里术语一律用 ZTerm.xxx。
//   2. 其余界面文案：Android app 与 design 模块 res/values*/strings.xml（术语表 keys.android 指向的键已被 term_* 取代，不再转换；
//      app_name 归 AppScope 所有，不进 entry，避免重名告警）。官方工具只出术语，界面文案仍由本脚本转换。
//   3. 本端专有文案 scripts/harmony-strings.json。
// base = 英文兜底，zh = 中文（与官方产物目录一致），其余 12 种语言按语言码目录。
// 用法：node apps/harmony/scripts/gen-strings.mjs [--check]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(scriptDir, '..');
const root = path.resolve(app, '../..');
const androidRes = path.join(root, 'apps/android/app/src/main/res');
// 设计系统模块（ZSheet“完成”等组件文案）同样并入；与 app 模块不重名。
const designRes = path.join(root, 'apps/android/design/src/main/res');
const extra = JSON.parse(fs.readFileSync(path.join(scriptDir, 'harmony-strings.json'), 'utf8'));
const resDir = path.join(app, 'entry/src/main/resources');

// Android values 后缀 → 鸿蒙资源限定词目录
const LOCALES = { '': 'base', zh: 'zh', ja: 'ja', ko: 'ko', ru: 'ru', es: 'es', fa: 'fa', tk: 'tk', my: 'my', ar: 'ar', ur: 'ur', sw: 'sw', tr: 'tr', vi: 'vi' };
const EXTRA_KEY = { '': 'en', zh: 'zh' };

const unescape = (s) => s
  .replace(/<[^>]+>/g, '')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&')
  .replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\(['"@?])/g, '$1').replace(/\\\\/g, '\\')
  .replace(/^"(.*)"$/s, '$1');

function parse(file) {
  const xml = fs.readFileSync(file, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const strings = []; const plurals = []; const arrays = [];
  for (const m of xml.matchAll(/<string\s+name="([a-z0-9_]+)"([^>]*)>([\s\S]*?)<\/string>/g)) {
    strings.push({ name: m[1], value: unescape(m[3].trim()), fixed: /translatable="false"/.test(m[2]) });
  }
  for (const m of xml.matchAll(/<plurals\s+name="([a-z0-9_]+)"[^>]*>([\s\S]*?)<\/plurals>/g)) {
    const value = [...m[2].matchAll(/<item\s+quantity="(\w+)">([\s\S]*?)<\/item>/g)].map((i) => ({ quantity: i[1], value: unescape(i[2].trim()) }));
    plurals.push({ name: m[1], value });
  }
  for (const m of xml.matchAll(/<string-array\s+name="([a-z0-9_]+)"[^>]*>([\s\S]*?)<\/string-array>/g)) {
    arrays.push({ name: m[1], value: [...m[2].matchAll(/<item>([\s\S]*?)<\/item>/g)].map((i) => ({ value: unescape(i[1].trim()) })) });
  }
  return { strings, plurals, arrays };
}

// 官方术语产物
const termsDir = path.join(root, 'tokens/generated/harmony');
const glossary = JSON.parse(fs.readFileSync(path.join(root, 'contract/i18n/glossary-v1.json'), 'utf8'));
const superseded = new Set(Object.values(glossary.terms).map((t) => t.keys && t.keys.android).filter(Boolean));
const DROP = new Set(['app_name']);
const termStrings = (dir) => {
  const f = path.join(termsDir, 'resources', dir, 'element/string.json');
  if (!fs.existsSync(f)) throw new Error(`缺官方术语产物：${path.relative(root, f)}（先在仓库根运行 node tools/gen-harmony-i18n.mjs）`);
  return JSON.parse(fs.readFileSync(f, 'utf8')).string;
};

const outs = {};
const json = (o) => JSON.stringify(o, null, 2) + '\n';
for (const [suffix, dir] of Object.entries(LOCALES)) {
  const file = path.join(androidRes, suffix ? `values-${suffix}` : 'values', 'strings.xml');
  if (!fs.existsSync(file)) continue;
  const p = parse(file);
  const dfile = path.join(designRes, suffix ? `values-${suffix}` : 'values', 'strings.xml');
  if (fs.existsSync(dfile)) {
    const d = parse(dfile);
    for (const x of d.strings) {
      if (p.strings.some((s) => s.name === x.name)) throw new Error(`design 模块文案与 app 重名：${x.name}`);
      p.strings.push(x);
    }
  }
  const strings = p.strings
    .filter((s) => (suffix === '' || !s.fixed) && !superseded.has(s.name) && !DROP.has(s.name))
    .map((s) => ({ name: s.name, value: s.value }));
  for (const t of termStrings(dir)) strings.push({ name: t.name, value: t.value });
  const own = extra[EXTRA_KEY[suffix] ?? ''] ?? {};
  if (suffix === '') {
    for (const k of Object.keys(extra.en)) if (strings.some((s) => s.name === k)) throw new Error(`harmony-strings.json 键与 Android 重名：${k}`);
  }
  for (const [name, value] of Object.entries(own)) strings.push({ name, value });
  strings.sort((a, b) => a.name.localeCompare(b.name));
  outs[path.join(resDir, dir, 'element/string.json')] = json({ string: strings });
  if (p.plurals.length) outs[path.join(resDir, dir, 'element/plural.json')] = json({ plural: p.plurals });
  if (p.arrays.length) outs[path.join(resDir, dir, 'element/strarray.json')] = json({ strarray: p.arrays });
}

outs[path.join(app, 'entry/src/main/ets/generated/ZTerms.ets')] = fs.readFileSync(path.join(termsDir, 'ZTerms.ets'), 'utf8');

const check = process.argv.includes('--check');
let dirty = false;
for (const [f, s] of Object.entries(outs)) {
  if (check) {
    if (!fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== s) { console.error(`过期：${path.relative(root, f)}`); dirty = true; }
  } else {
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, s);
  }
}
if (!check) console.log(`写出 ${Object.keys(outs).length} 个资源文件`);
process.exit(dirty ? 1 : 0);
