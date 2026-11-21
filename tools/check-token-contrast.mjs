#!/usr/bin/env node
// Token 对比度检查（零依赖）：解析 tokens 源（vendor/zephyr/packages/tokens/src/*.json + tokens/mobile.json，与 tokens/build.mjs 同一套合并/引用规则），
// 按下方 PAIRS 逐对计算浅色 / 深色两套的 WCAG 2.x 对比度。
// - 半透明前景（如 screen.t3 = rgba(…, 0.55)）先按 alpha 合成到背景上再算；半透明背景 screen.glass 合成到每个可能的底（bg / s1–s4）上取最差值。
// - Android 深色强调色（ZAccent.darkVariant，只读 apps/android）存在时一并检查。
// - 阈值：body = 4.5（AA 正文，字号 < 18pt 常规 / < 14pt 粗体）；ui = 3.0（AA 大字、图标、控件状态，WCAG 1.4.3 大字 / 1.4.11 非文本）。
// - 不达标但有意为之的组合写进 ALLOW（必须带 reason）；ALLOW 里的组合若已经达标，也会报错，提示删掉过期条目。
// 用法：node tools/check-token-contrast.mjs [--verbose] [--json]   失败退出 1。CI：.github/workflows/mobile.yml contract 作业。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8'));

// ---------- 解析（与 tokens/build.mjs 一致：桌面三份深合并，mobile.json 顶层追加；value = 深色，lightValue = 浅色） ----------
const deepMerge = (a, b) => {
  for (const [k, v] of Object.entries(b)) {
    if (v && typeof v === 'object' && !('value' in v)) a[k] = deepMerge(a[k] || {}, v);
    else a[k] = v;
  }
  return a;
};
const tree = ['primitive', 'semantic', 'component']
  .map((n) => read(`vendor/zephyr/packages/tokens/src/${n}.json`))
  .reduce((acc, t) => deepMerge(acc, t), {});
const mobile = read('tokens/mobile.json');
for (const k of Object.keys(mobile)) {
  if (k.startsWith('$')) continue;
  if (tree[k]) throw new Error(`mobile.json 顶层 ${k} 与桌面冲突`); // 与 build.mjs 同规则
  tree[k] = mobile[k];
}

const get = (p) => p.split('.').reduce((o, k) => (o ? o[k] : undefined), tree);
const resolve = (v, seen = new Set()) => {
  if (typeof v !== 'string') return v;
  return v.replace(/\{([^}]+)\}/g, (_, ref) => {
    if (seen.has(ref)) throw new Error(`循环引用 ${ref}`);
    const t = get(ref);
    if (!t || t.value === undefined) throw new Error(`无法解析引用 {${ref}}`);
    return resolve(t.value, new Set([...seen, ref]));
  });
};
const resolveLight = (tok) => resolve(tok.lightValue ?? (typeof tok.value === 'string' && /^\{[^}]+\}$/.test(tok.value) ? (get(tok.value.slice(1, -1)).lightValue ?? tok.value) : tok.value));

function parseColor(s) {
  s = String(s).trim();
  if (s === 'transparent') return [0, 0, 0, 0];
  let m;
  if ((m = s.match(/^#([0-9a-f]{3,8})$/i))) {
    let h = m[1];
    if (h.length <= 4) h = [...h].map((c) => c + c).join('');
    const n = (i) => parseInt(h.slice(i, i + 2), 16) / 255;
    return [n(0), n(2), n(4), h.length === 8 ? n(6) : 1];
  }
  if ((m = s.match(/^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+%?)\s*)?\)$/))) {
    const a = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
    return [m[1] / 255, m[2] / 255, m[3] / 255, a];
  }
  if ((m = s.match(/^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$/))) {
    const [h, sa, l] = [+m[1], m[2] / 100, m[3] / 100];
    const k = (n) => (n + h / 30) % 12;
    const f = (n) => l - sa * Math.min(l, 1 - l) * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1));
    return [f(0), f(8), f(4), m[4] === undefined ? 1 : +m[4]];
  }
  throw new Error(`无法解析颜色 ${s}`);
}

// 强调色不在 JSON 里，单一来源是 tokens/build.mjs 的 ACCENTS（两种模式同值）；从源码读，避免复制一份。
const accentSrc = fs.readFileSync(path.join(root, 'tokens/build.mjs'), 'utf8').match(/const ACCENTS = (\{[^}]+\})/);
if (!accentSrc) throw new Error('tokens/build.mjs 里找不到 ACCENTS');
const ACCENTS = Function(`return ${accentSrc[1]}`)();

// Android 深色下强调色用 ZAccent.darkVariant()（apps/android/design/…/ZColors.kt，B/C 所有，只读），值与 ACCENTS 不同；
// 读得到就按 Android 实际深色值再算一遍（token 名 accent.<name>@android），读不到（如只检出 tokens）则跳过。
const ANDROID_DARK = (() => {
  const f = path.join(root, 'apps/android/design/src/main/kotlin/com/zephyr/design/theme/ZColors.kt');
  if (!fs.existsSync(f)) return {};
  const body = fs.readFileSync(f, 'utf8').match(/fun ZAccent\.darkVariant\(\)[^{]*\{([^}]+)\}/);
  const out = {};
  for (const m of (body ? body[1] : '').matchAll(/ZAccent\.(\w+)\s*->\s*Color\(0x[0-9A-Fa-f]{2}([0-9A-Fa-f]{6})\)/g)) out[m[1].toLowerCase()] = `#${m[2]}`;
  return out;
})();

/** 'screen.t3' | 'accent.blue' → { light: [r,g,b,a], dark: [r,g,b,a] } */
function token(name) {
  if (name.startsWith('accent.') && name.endsWith('@android')) {
    const k = name.slice(7, -8);
    if (!ANDROID_DARK[k]) throw new Error(`Android 深色强调色缺 ${k}`);
    return { light: parseColor(ACCENTS[k]), dark: parseColor(ANDROID_DARK[k]) };
  }
  if (name.startsWith('accent.')) {
    const hex = ACCENTS[name.slice(7)];
    if (!hex) throw new Error(`未知强调色 ${name}`);
    const c = parseColor(hex);
    return { light: c, dark: c };
  }
  const t = get(name);
  if (!t || t.value === undefined) throw new Error(`未知 token ${name}`);
  return { dark: parseColor(resolve(t.value)), light: parseColor(resolveLight(t)) };
}

// ---------- WCAG ----------
const over = (fg, bg) => [0, 1, 2].map((i) => fg[i] * fg[3] + bg[i] * (1 - fg[3])).concat(1);
const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const lum = ([r, g, b]) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
const hex = (c) => '#' + c.slice(0, 3).map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('').toUpperCase();

const T = { body: 4.5, ui: 3.0 };

// ---------- 检查的组合 ----------
// 背景：screen.bg 页面底、screen.s1 卡片、screen.s2 卡片内嵌 / 列表、screen.s3 控件底（搜索框、分段）、screen.s4 按下 / 分段选中 / 浮起表面（ZSurface.elevated、吐司）、
// screen.glass 指令栏 / 浮层玻璃——玻璃下面可能是任一表面，按 GLASS_BACKDROPS 逐个合成取最差值。
const SURFACES = ['screen.bg', 'screen.s1', 'screen.s2', 'screen.s3', 'screen.s4', 'screen.glass'];
const GLASS_BACKDROPS = ['screen.bg', 'screen.s1', 'screen.s2', 'screen.s3', 'screen.s4'];
const CARDS = ['screen.s1', 'screen.s2'];
const PAIRS = [
  // 正文文字层级（t1 主、t2 次、t3 三级说明 / 占位）——正文阈值
  ...['screen.t1', 'screen.t2', 'screen.t3'].flatMap((fg) => SURFACES.map((bg) => ({ fg, bg, level: 'body' }))),
  // 主按钮文字
  { fg: 'screen.on-primary', bg: 'screen.primary', level: 'body' },
  // 延迟读数（节点行 / 场景候选 / 小组件，12–15pt 等宽）——正文阈值
  ...['latency.normal', 'latency.unknown', 'latency.slow', 'latency.timeout'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'body' }))),
  // 状态色作文字（订阅「剩余 / 到期」警示、更新 diff +/−、连接失败、已连接）——正文阈值
  ...['screen.amber', 'screen.red', 'screen.green'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'body' }))),
  // 实时速率箭头 / 上下行图标——UI 阈值
  ...['color.download', 'screen.up'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'ui' }))),
  // 强调色：返回链接、索引条、搜索高亮、「+」按钮、开关 / 进度填充——UI 阈值（大字 / 图标 / 控件）
  ...Object.keys(ACCENTS).flatMap((a) => ['screen.bg', 'screen.s1'].map((bg) => ({ fg: `accent.${a}`, bg, level: 'ui' }))),
  // 默认强调色作小号文字（提示语、索引条、搜索命中高亮）——正文阈值；其余强调色作文字时同理，但用户可选色不进 CI
  ...['screen.bg', 'screen.s1', 'screen.s4'].map((bg) => ({ fg: 'accent.blue', bg, level: 'body', note: 'small-text' })),
  // 强调色底上的白字（主按钮 15pt、选中胶囊 14pt——都不到「大字」，按正文 4.5）
  ...Object.keys(ACCENTS).map((a) => ({ fg: 'text.on-accent', bg: `accent.${a}`, level: 'body' })),
  // Android 深色实际强调色（darkVariant）
  ...Object.keys(ANDROID_DARK).flatMap((a) => [
    ...['screen.bg', 'screen.s1'].map((bg) => ({ fg: `accent.${a}@android`, bg, level: 'ui', modes: ['dark'] })),
    { fg: 'text.on-accent', bg: `accent.${a}@android`, level: 'body', modes: ['dark'] },
  ]),
  // 四级文字 t4：只用于禁用态、装饰性箭头 / 分隔符号（WCAG 1.4.3 对禁用和纯装饰豁免）——仍列出，确保有人改它时看得到
  ...['screen.bg', 'screen.s1'].map((bg) => ({ fg: 'screen.t4', bg, level: 'ui' })),
];

// ---------- 允许清单：key = `${fg}|${bg}|${mode}`；kind = intentional（有意）| debt（已知欠账，修复需改 token 并重录两端基线） ----------
const ALLOW = {};
const allow = (fgs, bgs, modes, kind, reason) => { for (const f of fgs) for (const b of bgs) for (const m of modes) ALLOW[`${f}|${b}|${m}`] = { kind, reason }; };
allow(['screen.t4'], ['screen.bg', 'screen.s1'], ['light', 'dark'], 'debt',
  't4 设计上只给禁用态、装饰分隔、sheet 把手（WCAG 1.4.3 豁免）；但目前还承载可读信息：iOS 规则序号（ZSettingsRow）、iOS 未测延迟「···」（ZLatencyPill）、两端可点行的 chevron。修复：这些改用 t3 / latency.unknown，之后本条可改回 intentional');
allow(['accent.green', 'accent.orange'], ['screen.bg', 'screen.s1'], ['light'], 'debt',
  '可选强调色 green / orange（Apple 系统色）在浅色底上 2.0–2.2:1；用户选了它们时，返回链接、「+」、索引条等强调色前景也随之变色。修复：浅色下强调色前景用加深变体（如 green #248A3D、orange #C93400），填充保持系统色');
allow(['text.on-accent'], ['accent.blue', 'accent.pink', 'accent.green', 'accent.orange'], ['light', 'dark'], 'debt',
  '强调色底上的白字（主按钮 15pt semibold、选中胶囊）是正文字号：blue 4.02、pink 3.65、green / orange 约 2.2:1，与 iOS 系统按钮同款但不达 AA 4.5。修复：green / orange 底改黑字，blue / pink 底加深约 10%');
allow(['text.on-accent'], ['accent.blue@android', 'accent.pink@android', 'accent.green@android', 'accent.orange@android'], ['dark'], 'debt',
  'Android 深色 darkVariant 更亮（#0A84FF / #FF375F / #30D158 / #FF9F0A），白字 2.0–3.65:1。同上；另：深色变体应提到 tokens 作为单一来源');
allow(['screen.t3'], ['screen.s4'], ['light'], 'debt',
  '浅色 t3 在 s4（#DCDCE1，ZSurface.elevated / 按下态）上 4.39:1，差 0.11。修复：浅色 s4 提亮到约 #E3E3E8，或 elevated 表面上的说明文字用 t2');
allow(['screen.amber', 'latency.slow'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '浅色 amber #FF9F0A 作文字约 2.0–2.2:1（订阅「剩余 / 到期」、延迟 ≥200ms、小组件「连接失败」副标题）。修复：加浅色专用文字色（如 #B25000）并重录基线；见 design-review 2026-11-21');
allow(['screen.green'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '浅色 green #34C759 作文字约 2.2:1（订阅更新 diff「+1,204」）。修复同上（如 #248A3D）');
allow(['screen.red', 'latency.timeout'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '浅色 red #FF3B30 作文字约 3.4–3.6:1，达 UI 阈值但不达正文 4.5（「−318」、超时）。修复同上（如 #D70015）');
allow(['screen.up'], ['screen.bg'], ['light'], 'debt',
  '浅色上行箭头 #FF5E57 在 #F2F2F7 页面底上 2.69:1（卡片上恰 3.0）；旁边有「KB/s」与数值冗余表达。修复时与 color.upload（浅 #D13A3F，iOS 已在用）统一');
ALLOW['accent.blue|screen.s4|light|text'] = ALLOW['accent.blue|screen.s4|dark|text'] = { kind: 'debt', reason:
  '强调色小字在 s4（ZSurface.elevated，如 PageErrorBanner 的「重试」链接）上：浅色 2.94、深色 3.75:1。修复：elevated 表面上的链接用 t1 加下划线，或改用 s2 表面' };
for (const b of ['screen.bg', 'screen.s1']) ALLOW[`accent.blue|${b}|light|text`] = { kind: 'debt', reason:
  '默认强调色 #007AFF 作小号文字（首页场景卡「左右滑动以切换地区」、节点页索引条 10pt、搜索高亮）在浅色下 3.6–4.0:1，达 UI 阈值不达正文。修复：小字改用 t2 或加 accent 文字专用浅色变体（如 #0062CC）' };

// ---------- 运行 ----------
const args = new Set(process.argv.slice(2));
const rows = [];
for (const p of PAIRS) {
  const f = token(p.fg), b = token(p.bg);
  for (const mode of p.modes || ['light', 'dark']) {
    // 半透明背景：合成到每个可能的底上，取对比度最低的那个
    const backs = b[mode][3] < 1 ? (p.bg === 'screen.glass' ? GLASS_BACKDROPS : ['screen.bg']).map((n) => over(b[mode], token(n)[mode])) : [b[mode]];
    let bg, fg, r = Infinity;
    for (const cand of backs) { const fgc = over(f[mode], cand); const rc = ratio(fgc, cand); if (rc < r) { r = rc; bg = cand; fg = fgc; } }
    const need = T[p.level];
    const key = `${p.fg}|${p.bg}|${mode}${p.level === 'body' && p.fg.startsWith('accent.') ? '|text' : ''}`;
    rows.push({ ...p, mode, ratio: +r.toFixed(2), need, pass: r >= need, allow: ALLOW[key], fgHex: hex(fg), bgHex: hex(bg), key });
  }
}
const fails = rows.filter((r) => !r.pass && !r.allow);
const stale = Object.keys(ALLOW).filter((k) => { const r = rows.find((x) => x.key === k); return !r || r.pass; });

if (args.has('--json')) {
  console.log(JSON.stringify({ rows, fails: fails.map((r) => r.key), stale }, null, 2));
} else {
  const line = (r) => `${r.mode.padEnd(5)} ${r.fg.padEnd(16)} on ${r.bg.padEnd(14)} ${r.fgHex} / ${r.bgHex}  ${r.ratio.toFixed(2).padStart(5)}:1  (≥${r.need} ${r.level})`;
  if (args.has('--verbose')) for (const r of rows) console.log(`${r.pass ? 'ok  ' : r.allow ? (r.allow.kind === 'debt' ? 'DEBT' : 'allow') : 'FAIL'} ${line(r)}`);
  const allowed = rows.filter((r) => !r.pass && r.allow);
  console.log(`对比度：${rows.length} 组（${PAIRS.length} 对 × 浅/深），达标 ${rows.filter((r) => r.pass).length}，允许清单 ${allowed.length}（其中已知欠账 ${allowed.filter((r) => r.allow.kind === 'debt').length}），失败 ${fails.length}`);
  for (const r of fails) console.log(`FAIL ${line(r)}`);
  for (const k of stale) console.log(`STALE 允许清单条目已达标或不存在，请删除：${k}`);
}
process.exit(fails.length || stale.length ? 1 : 0);
