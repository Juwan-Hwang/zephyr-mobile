#!/usr/bin/env node
// 鸿蒙端本地文案转换（角色 D，临时方案）。只读 Android 的 res/values*/strings.xml（键名与 contract/i18n/glossary-v1.json
// 的 keys.android 一致，术语因此天然对齐），外加本端专有文案 scripts/harmony-strings.json，生成：
//   entry/src/main/resources/<限定词>/element/{string,plural,strarray}.json
// base = 英文（与 Android values/ 一样作兜底），zh_CN = 简体中文，其余 12 种语言按语言码目录。
// 待 A 在官方 i18n 工具里加 ArkTS / 鸿蒙资源产物后删除本脚本（见 #241「请 A 协助」3）。
// 用法：node apps/harmony/scripts/gen-strings.mjs [--check]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(scriptDir, '..');
const root = path.resolve(app, '../..');
const androidRes = path.join(root, 'apps/android/app/src/main/res');
const extra = JSON.parse(fs.readFileSync(path.join(scriptDir, 'harmony-strings.json'), 'utf8'));
const resDir = path.join(app, 'entry/src/main/resources');

// Android values 后缀 → 鸿蒙资源限定词目录
const LOCALES = { '': 'base', zh: 'zh_CN', ja: 'ja', ko: 'ko', ru: 'ru', es: 'es', fa: 'fa', tk: 'tk', my: 'my', ar: 'ar', ur: 'ur', sw: 'sw', tr: 'tr', vi: 'vi' };
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

const outs = {};
const json = (o) => JSON.stringify(o, null, 2) + '\n';
for (const [suffix, dir] of Object.entries(LOCALES)) {
  const file = path.join(androidRes, suffix ? `values-${suffix}` : 'values', 'strings.xml');
  if (!fs.existsSync(file)) continue;
  const p = parse(file);
  const strings = p.strings.filter((s) => suffix === '' || !s.fixed).map((s) => ({ name: s.name, value: s.value }));
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
