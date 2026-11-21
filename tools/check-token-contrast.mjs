#!/usr/bin/env node
// Token 对比度检查（零依赖）：解析 tokens 源（vendor/zephyr/packages/tokens/src/*.json + tokens/mobile.json，与 tokens/build.mjs 同一套合并/引用规则），
// 按下方 PAIRS 逐对计算浅色 / 深色两套的 WCAG 2.x 对比度。
// - 半透明前景（如 screen.t3 = rgba(…, 0.55)）先按 alpha 合成到背景上再算；半透明背景 screen.glass 合成到每个可能的底（bg / s1–s4）上取最差值。
// - 强调色读 tokens/mobile.json accent.*（含深色变体，原 Android ZColors.kt darkVariant 已提到 tokens）；ZColors.kt 若仍自带一份且不一致，只告警。
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

// 强调色：mobile.json accent.<name>.{base,text,fill,on-fill}（value = 深色、lightValue = 浅色），tokens/build.mjs 同源。
// `accent.<name>`（两段）= 历史单一值（浅色 base，两种模式同值）——平台目前就这样用，作为「旧用法」继续检查，直到 B/C/D 切到新变体。
const ACCENT_NAMES = Object.keys(tree.accent || {}).filter((k) => !k.startsWith('$'));
if (!ACCENT_NAMES.length) throw new Error('tokens/mobile.json 缺 accent 组');
const ACCENTS = Object.fromEntries(ACCENT_NAMES.map((k) => [k, resolveLight(tree.accent[k].base)]));

// Android 深色强调色过去只写在 apps/android/…/ZColors.kt 的 ZAccent.darkVariant()（C 所有，只读）。现在单一来源是 accent.<name>.base 的深色值；
// 若 ZColors.kt 仍有自己的一份，与 tokens 不一致时只告警（不失败），提示 C 改为 ZAccent.base(dark) / colorDark。
const ANDROID_DARK = (() => {
  const f = path.join(root, 'apps/android/design/src/main/kotlin/com/zephyr/design/theme/ZColors.kt');
  if (!fs.existsSync(f)) return {};
  const body = fs.readFileSync(f, 'utf8').match(/fun ZAccent\.darkVariant\(\)[^{]*\{([^}]+)\}/);
  const out = {};
  for (const m of (body ? body[1] : '').matchAll(/ZAccent\.(\w+)\s*->\s*Color\(0x[0-9A-Fa-f]{2}([0-9A-Fa-f]{6})\)/g)) out[m[1].toLowerCase()] = `#${m[2]}`.toUpperCase();
  return out;
})();

/** 'screen.t3' | 'accent.blue' → { light: [r,g,b,a], dark: [r,g,b,a] } */
function token(name) {
  const parts = name.split('.');
  if (parts[0] === 'accent' && parts.length === 2) {
    const hex = ACCENTS[parts[1]];
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
  ...['screen.amber-text', 'screen.red-text', 'screen.green-text'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'body' }))),
  // 旧用法：原状态色直接作文字（平台切到 *-text 后删除这组 PAIRS 与对应 ALLOW；之后 amber / green / red 只作圆点 / 进度条 / 图标，且必配形状或文字）
  ...['screen.amber', 'screen.red', 'screen.green'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'body' }))),
  // 实时速率箭头 / 上下行图标——UI 阈值
  ...['color.download', 'screen.up'].flatMap((fg) => [...CARDS, 'screen.bg'].map((bg) => ({ fg, bg, level: 'ui' }))),
  // —— 强调色新变体（单一来源 mobile.json accent.*；平台切换后这些就是实际用法）——
  // base 深色（开关 / 进度 / 光晕 / 选中描边；原 Android darkVariant）——UI 阈值；浅色 base = 历史单一值，见下方旧用法
  ...ACCENT_NAMES.flatMap((a) => ['screen.bg', 'screen.s1'].map((bg) => ({ fg: `accent.${a}.base`, bg, level: 'ui', modes: ['dark'] }))),
  // text：前景小字 / 链接 / 索引条 / 搜索高亮 / 图标——正文阈值；含 s4（ZSurface.elevated 上的「重试」链接，用户选哪个强调色都会出现）
  ...ACCENT_NAMES.flatMap((a) => ['screen.bg', 'screen.s1', 'screen.s4'].map((bg) => ({ fg: `accent.${a}.text`, bg, level: 'body' }))),
  // fill + on-fill：主按钮 15pt / 选中胶囊 14pt——正文阈值
  ...ACCENT_NAMES.map((a) => ({ fg: `accent.${a}.on-fill`, bg: `accent.${a}.fill`, level: 'body' })),
  // —— 旧用法（平台尚未切换到上面的变体；切换后删除这些 PAIRS 及 ALLOW 条目）——
  // 强调色单一值作前景（返回链接、索引条、「+」、开关填充）——UI 阈值
  ...ACCENT_NAMES.flatMap((a) => ['screen.bg', 'screen.s1'].map((bg) => ({ fg: `accent.${a}`, bg, level: 'ui' }))),
  // 默认强调色单一值作小号文字——正文阈值
  ...['screen.bg', 'screen.s1', 'screen.s4'].map((bg) => ({ fg: 'accent.blue', bg, level: 'body', note: 'small-text' })),
  // 强调色底上的白字（text.on-accent，桌面 token）：浅色底 = 单一值，深色底 = base 深色（Android 现状）
  ...ACCENT_NAMES.map((a) => ({ fg: 'text.on-accent', bg: `accent.${a}`, level: 'body' })),
  ...ACCENT_NAMES.map((a) => ({ fg: 'text.on-accent', bg: `accent.${a}.base`, level: 'body', modes: ['dark'] })),
  // 四级文字 t4：只用于禁用态、装饰性箭头 / 分隔符号（WCAG 1.4.3 对禁用和纯装饰豁免）——仍列出，确保有人改它时看得到
  ...['screen.bg', 'screen.s1'].map((bg) => ({ fg: 'screen.t4', bg, level: 'ui' })),
];

// ---------- 允许清单：key = `${fg}|${bg}|${mode}`；kind = intentional（有意）| debt（已知欠账，修复需改 token 并重录两端基线） ----------
const ALLOW = {};
const allow = (fgs, bgs, modes, kind, reason) => { for (const f of fgs) for (const b of bgs) for (const m of modes) ALLOW[`${f}|${b}|${m}`] = { kind, reason }; };
allow(['screen.t4'], ['screen.bg', 'screen.s1'], ['light', 'dark'], 'debt',
  '旧用法：t4 设计上只给禁用态、装饰分隔、sheet 把手（WCAG 1.4.3 豁免）；但目前还承载可读信息：iOS 规则序号（ZSettingsRow）、iOS 未测延迟「···」（ZLatencyPill）、两端可点行的 chevron。修复：这些改用 t3 / latency.unknown，之后本条可改回 intentional');
allow(['accent.green', 'accent.orange'], ['screen.bg', 'screen.s1'], ['light'], 'debt',
  '旧用法：可选强调色 green / orange 单一值在浅色底上 2.0–2.2:1，被平台当作返回链接、「+」、索引条等前景。tokens 已给 accent.*.text（浅色 green #1F7A35、orange #C93400，均 ≥4.7）；平台前景改用 ZAccent.text / ZTokens.Accent.text 后，本条改为 intentional（单一值只作开关 / 进度填充，开关状态另有滑块位置表达）');
allow(['text.on-accent'], ['accent.blue', 'accent.pink', 'accent.green', 'accent.orange'], ['light', 'dark'], 'debt',
  '旧用法：强调色单一值底上的白字（主按钮 15pt semibold、选中胶囊）：blue 4.02、pink 3.65、green / orange 约 2.2:1。tokens 已给 accent.*.fill + on-fill（blue #0066D6 / pink #D1004B 白字 5.4–5.5，green / orange 黑字 ≥9.5）；平台改用 ZAccent.fill/onFill 后删除本条');
allow(['text.on-accent'], ['accent.blue.base', 'accent.pink.base', 'accent.green.base', 'accent.orange.base'], ['dark'], 'debt',
  '旧用法：Android 深色在 darkVariant（= accent.*.base 深色 #0A84FF / #FF375F / #30D158 / #FF9F0A）底上写白字，2.0–3.65:1。同上，改用 fill/onFill 后删除本条');
allow(['screen.amber'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '旧用法：浅色 amber #FF9F0A 作文字约 1.8–2.1:1（订阅「剩余 / 到期」、小组件「连接失败」副标题）。tokens 已给 screen.amber-text（浅色 #B25000，4.66–5.20）；平台改用后删除本条');
allow(['screen.green'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '旧用法：浅色 green #34C759 作文字约 2.0–2.2:1（订阅更新 diff「+1,204」）。改用 screen.green-text（#1F7A35，4.83–5.39）后删除本条');
allow(['screen.red'], ['screen.bg', 'screen.s1', 'screen.s2'], ['light'], 'debt',
  '旧用法：浅色 red #FF3B30 作文字约 3.2–3.6:1（「−318」）。改用 screen.red-text（#D70015，4.83–5.38）后删除本条');
ALLOW['accent.blue|screen.s4|light|text'] = ALLOW['accent.blue|screen.s4|dark|text'] = { kind: 'debt', reason:
  '旧用法：强调色单一值小字在 s4（ZSurface.elevated，如 PageErrorBanner 的「重试」链接）上：浅色 2.94、深色 3.75:1。改用 accent.blue.text（浅色 4.73、深色 5.32）后删除本条' };
for (const b of ['screen.bg', 'screen.s1']) ALLOW[`accent.blue|${b}|light|text`] = { kind: 'debt', reason:
  '旧用法：默认强调色单一值 #007AFF 作小号文字（首页场景卡「左右滑动以切换地区」、节点页索引条、搜索高亮）在浅色下 3.6–4.0:1。改用 accent.blue.text（浅色 #005BBF，5.8–6.5）后删除本条' };

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
const warns = Object.entries(ANDROID_DARK).filter(([k, v]) => { const t = tree.accent[k]; return !t || hex(parseColor(resolve(t.base.value))) !== v; })
  .map(([k, v]) => `WARN apps/android ZColors.kt darkVariant ${k} = ${v}，与 tokens accent.${k}.base 深色不一致（请改用 ZAccent.base(dark)）`);
const stale = Object.keys(ALLOW).filter((k) => { const r = rows.find((x) => x.key === k); return !r || r.pass; });

if (args.has('--json')) {
  console.log(JSON.stringify({ rows, fails: fails.map((r) => r.key), stale, warns }, null, 2));
} else {
  const line = (r) => `${r.mode.padEnd(5)} ${r.fg.padEnd(16)} on ${r.bg.padEnd(14)} ${r.fgHex} / ${r.bgHex}  ${r.ratio.toFixed(2).padStart(5)}:1  (≥${r.need} ${r.level})`;
  if (args.has('--verbose')) for (const r of rows) console.log(`${r.pass ? 'ok  ' : r.allow ? (r.allow.kind === 'debt' ? 'DEBT' : 'allow') : 'FAIL'} ${line(r)}`);
  const allowed = rows.filter((r) => !r.pass && r.allow);
  console.log(`对比度：${rows.length} 组（${PAIRS.length} 对 × 浅/深），达标 ${rows.filter((r) => r.pass).length}，允许清单 ${allowed.length}（其中已知欠账 ${allowed.filter((r) => r.allow.kind === 'debt').length}，含待平台切换的旧用法 ${allowed.filter((r) => r.allow.kind === 'debt' && r.allow.reason.startsWith('旧用法')).length}），失败 ${fails.length}`);
  for (const r of fails) console.log(`FAIL ${line(r)}`);
  for (const w of warns) console.log(w);
  for (const k of stale) console.log(`STALE 允许清单条目已达标或不存在，请删除：${k}`);
}
process.exit(fails.length || stale.length ? 1 : 0);
