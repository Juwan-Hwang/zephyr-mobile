#!/usr/bin/env node
// 三端共用术语（contract/i18n/glossary-v1.json）对齐检查：只读 apps 下的译文，不改任何文件。
//  1. 每个术语映射到的 Android 字符串 / iOS 字符串，在 14 种语言里都要等于终版译名
//     （忽略大小写；tr 按土耳其语规则折叠；ar 忽略词首定冠词 ال；tr 撇号统一为 ’）。
//  2. 未对齐项必须列在 contract/i18n/glossary-pending.json；已对齐却仍在豁免表里的报“过期豁免”。
//     带格式占位符的整句只要求包含术语；keysPlanned 是已定名、平台尚未接入的键，不检查。
//  3. 土库曼语（tk）译文不得出现 ı / ğ（土耳其语字母，tk 字母表没有）。
// 用法：node tools/check-glossary.mjs [--desktop <Zephyr 仓库路径>]
//   --desktop：额外打印桌面端 i18n.js 中与终版不一致的同名术语（仅提示，不计入失败）。
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const glossary = JSON.parse(readFileSync(join(root, 'contract/i18n/glossary-v1.json'), 'utf8'));
const pending = new Set(JSON.parse(readFileSync(join(root, 'contract/i18n/glossary-pending.json'), 'utf8')).pending);
const LANGS = glossary.locales;
const errors = [];

const unescapeXml = (s) =>
  s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/\\'/g, "'")
    .replace(/\\"/g, '"');

function loadAndroid() {
  const out = {};
  const res = join(root, 'apps/android/app/src/main/res');
  for (const l of LANGS) {
    out[l] = {};
    const dir = join(res, l === 'en' ? 'values' : `values-${l}`);
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir).filter((n) => n.endsWith('.xml'))) {
      const xml = readFileSync(join(dir, f), 'utf8');
      for (const m of xml.matchAll(/<string name="([^"]+)"[^>]*>([\s\S]*?)<\/string>/g)) out[l][m[1]] = unescapeXml(m[2]);
    }
  }
  return out;
}

function loadIos() {
  const out = Object.fromEntries(LANGS.map((l) => [l, {}]));
  const files = { App: 'apps/ios/App/Localizable.xcstrings', Widgets: 'apps/ios/Widgets/Localizable.xcstrings' };
  for (const [tag, path] of Object.entries(files)) {
    const doc = JSON.parse(readFileSync(join(root, path), 'utf8'));
    for (const [key, entry] of Object.entries(doc.strings)) {
      for (const l of LANGS) {
        const loc = l === 'zh' ? 'zh-Hans' : l;
        let v = entry.localizations?.[loc]?.stringUnit?.value;
        if (v === undefined && loc === doc.sourceLanguage) v = key.replace(/#.*$/, '');
        if (v !== undefined) out[l][`${tag}:${key}`] = v;
      }
    }
  }
  return out;
}

const fold = (s, l) => {
  let t = s.trim().replace(/[.。…:：]+$/, '').replace(/'/g, '’');
  t = l === 'tr' ? t.toLocaleLowerCase('tr') : t.toLowerCase();
  if (l === 'ar') t = t.replace(/(^|\s)ال/g, '$1');
  return t;
};

const FORMAT = /%(\d+\$)?(@|s|d|lld|ld)/;
const platforms = { android: loadAndroid(), ios: loadIos() };
const seen = new Set();
for (const [term, entry] of Object.entries(glossary.terms)) {
  for (const l of LANGS) if (typeof entry[l] !== 'string' || !entry[l]) errors.push(`术语 ${term} 缺少 ${l}`);
  for (const [p, key] of Object.entries(entry.keys ?? {})) {
    for (const l of LANGS) {
      const got = platforms[p][l][key];
      const id = `${p} ${term} ${l}`;
      if (got === undefined) {
        errors.push(`${id}: 找不到键 ${key}`);
        continue;
      }
      // 带格式占位符的整句（iOS %@ / %1$@、Android %s / %1$s / %d）：术语出现在句中即可，如「可连通 %1$@ · 已检测 %2$@」含「可连通」
      const ok = FORMAT.test(got) ? fold(got, l).includes(fold(entry[l], l)) : fold(got, l) === fold(entry[l], l);
      if (ok && pending.has(id)) errors.push(`${id}: 已对齐，请从 glossary-pending.json 删除（过期豁免）`);
      if (!ok && !pending.has(id)) errors.push(`${id}: 「${got}」应为「${entry[l]}」`);
      seen.add(id);
    }
  }
}
for (const id of pending) if (!seen.has(id)) errors.push(`豁免 ${id} 不对应任何术语映射`);

for (const [p, data] of Object.entries(platforms))
  for (const [k, v] of Object.entries(data.tk ?? {})) if (/[ıİğĞ]/.test(v)) errors.push(`${p} tk ${k}: 含土耳其语字母 ı/ğ：「${v}」`);

const di = process.argv.indexOf('--desktop');
if (di > 0) {
  const src = readFileSync(join(process.argv[di + 1], 'apps/desktop/src/i18n.js'), 'utf8');
  const a = src.indexOf('export const translations = ');
  const b = src.indexOf('\n};', a);
  const desk = Function(`return ${src.slice(a + 'export const translations = '.length, b + 2)}`)();
  const byEn = {};
  for (const [k, v] of Object.entries(desk.en)) if (typeof v === 'string') (byEn[fold(v, 'en')] ??= []).push(k);
  let n = 0;
  for (const [term, entry] of Object.entries(glossary.terms))
    for (const k of byEn[fold(entry.en, 'en')] ?? [])
      for (const l of LANGS)
        if (typeof desk[l]?.[k] === 'string' && fold(desk[l][k], l) !== fold(entry[l], l)) {
          console.log(`desktop ${term} ${l} ${k}: 「${desk[l][k]}」（终版「${entry[l]}」）`);
          n++;
        }
  console.log(`desktop：${n} 处同名术语与终版不同（仅提示；桌面同一英文词可能有不同语境）`);
}

if (errors.length) {
  console.error(errors.join('\n'));
  console.error(`check-glossary：${errors.length} 个问题`);
  process.exit(1);
}
console.log(`check-glossary：${Object.keys(glossary.terms).length} 个术语 × ${LANGS.length} 种语言，豁免 ${pending.size} 项，OK`);
