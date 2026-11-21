#!/usr/bin/env node
// 鸿蒙端 tokens 同步（角色 D）。
// 默认：A 的官方生成器已产出 ArkTS（tokens/build.mjs → tokens/generated/harmony/，#242 已合），本脚本只**拷贝**它：
//   tokens/generated/harmony/ZTokens.ets                          → entry/src/main/ets/generated/ZTokens.ets
//   tokens/generated/harmony/resources/{base,dark}/element/color.json → entry/src/main/resources/{base,dark}/element/color.json
//   （color.json 末尾追加 start_window_background = screen_bg，供 module.json5 startWindowBackground 引用）
// 颜色资源名以官方产物为准：$r('app.color.<snake_name>')，如 app.color.text_primary。
// --local：退回旧的本地转换（读 tokens/ 与 vendor/zephyr 桌面 token，资源名带 z_ 前缀），仅在官方产物缺失时用；待确认无用后删除。
// 输出禁止手改。用法：node apps/harmony/scripts/gen-tokens.mjs [--check] [--local]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(scriptDir, '..');
const root = path.resolve(app, '../..');
const here = path.join(root, 'tokens');
const check = process.argv.includes('--check');
const upstream = path.join(root, 'tokens/generated/harmony');
if (!process.argv.includes('--local') && fs.existsSync(path.join(upstream, 'ZTokens.ets'))) {
  const withStart = (file) => {
    const res = JSON.parse(fs.readFileSync(file, 'utf8'));
    const bg = res.color.find((c) => c.name === 'screen_bg');
    if (!bg) throw new Error(`${path.relative(root, file)} 缺少 screen_bg`);
    res.color = res.color.filter((c) => c.name !== 'start_window_background').concat([{ name: 'start_window_background', value: bg.value }]);
    return JSON.stringify(res, null, 2) + '\n';
  };
  const copies = {
    [path.join(app, 'entry/src/main/ets/generated/ZTokens.ets')]: fs.readFileSync(path.join(upstream, 'ZTokens.ets'), 'utf8'),
    [path.join(app, 'entry/src/main/resources/base/element/color.json')]: withStart(path.join(upstream, 'resources/base/element/color.json')),
    [path.join(app, 'entry/src/main/resources/dark/element/color.json')]: withStart(path.join(upstream, 'resources/dark/element/color.json')),
  };
  let stale = false;
  for (const [f, s] of Object.entries(copies)) {
    if (check) {
      if (!fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== s) { console.error(`过期：${path.relative(root, f)}`); stale = true; }
    } else {
      fs.mkdirSync(path.dirname(f), { recursive: true });
      fs.writeFileSync(f, s);
      console.log(`拷贝 ${path.relative(root, f)}`);
    }
  }
  process.exit(stale ? 1 : 0);
}
const desktopDir = path.join(root, 'vendor/zephyr/packages/tokens/src');
const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
if (!fs.existsSync(desktopDir)) { console.error('缺少 vendor/zephyr 子模块：git submodule update --init vendor/zephyr'); process.exit(2); }

const desktop = ['primitive', 'semantic', 'component'].map((n) => read(path.join(desktopDir, `${n}.json`)));
const mobile = read(path.join(here, 'mobile.json'));

// ---------- 合并与引用解析 ----------
const merge = (a, b) => {
  for (const [k, v] of Object.entries(b)) {
    if (k.startsWith('$')) continue;
    if (v && typeof v === 'object' && !('value' in v) && a[k] && typeof a[k] === 'object') merge(a[k], v);
    else if (a[k] && typeof a[k] === 'object' && !('value' in a[k]) && v && typeof v === 'object' && !('value' in v)) merge(a[k], v);
    else {
      if (a[k] !== undefined && k !== 'shadow') throw new Error(`mobile.json 不得覆盖桌面 token：${k}`);
      a[k] = v;
    }
  }
  return a;
};
// 桌面三份之间允许同名顶层（shadow 在 primitive 与 semantic 都有），按路径深合并
const deepMerge = (a, b) => {
  for (const [k, v] of Object.entries(b)) {
    if (v && typeof v === 'object' && !('value' in v)) a[k] = deepMerge(a[k] || {}, v);
    else a[k] = v;
  }
  return a;
};
const tree = desktop.reduce((acc, t) => deepMerge(acc, t), {});
const mobileKeys = Object.keys(mobile).filter((k) => !k.startsWith('$'));
for (const k of mobileKeys) {
  if (tree[k]) throw new Error(`mobile.json 顶层 ${k} 与桌面冲突`);
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

const leaves = (node, p = []) => {
  if (node && typeof node === 'object' && 'value' in node) return [{ path: p, tok: node }];
  return Object.entries(node || {}).filter(([k]) => !k.startsWith('$')).flatMap(([k, v]) => leaves(v, [...p, k]));
};

// ---------- 值解析 ----------
const clamp = (x) => Math.max(0, Math.min(1, x));
function parseColor(s) {
  s = String(s).trim();
  if (s === 'transparent') return [0, 0, 0, 0];
  let m;
  if ((m = s.match(/^#([0-9a-f]{3,8})$/i))) {
    let h = m[1];
    if (h.length === 3 || h.length === 4) h = [...h].map((c) => c + c).join('');
    const n = (i) => parseInt(h.slice(i, i + 2), 16) / 255;
    return [n(0), n(2), n(4), h.length === 8 ? n(6) : 1];
  }
  if ((m = s.match(/^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+%?)\s*)?\)$/))) {
    const a = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
    return [m[1] / 255, m[2] / 255, m[3] / 255, a];
  }
  if ((m = s.match(/^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$/))) {
    const [h, sa, l] = [+m[1], m[2] / 100, m[3] / 100];
    const a = m[4] === undefined ? 1 : +m[4];
    const k = (n) => (n + h / 30) % 12;
    const f = (n) => l - sa * Math.min(l, 1 - l) * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1));
    return [f(0), f(8), f(4), a];
  }
  return null;
}
const num = (s) => {
  const m = String(s).trim().match(/^(-?[\d.]+)(px|rem|em|ms|s|%)?$/);
  if (!m) return null;
  const v = parseFloat(m[1]);
  return { px: v, rem: v * 16, em: v * 16, ms: v, s: v * 1000, '%': v / 100 }[m[2] || 'px'] ?? v;
};
const bezier = (s) => {
  const m = String(s).match(/cubic-bezier\(\s*([\d.-]+)\s*,\s*([\d.-]+)\s*,\s*([\d.-]+)\s*,\s*([\d.-]+)\s*\)/);
  return m ? m.slice(1).map(Number) : null;
};
const camel = (parts) => {
  const s = parts.join('-').replace(/[^a-zA-Z0-9]+(.)/g, (_, c) => c.toUpperCase()).replace(/[^a-zA-Z0-9]/g, '');
  return /^\d/.test(s) ? `n${s}` : s;
};
const f3 = (x) => clamp(x).toFixed(4).replace(/0+$/, '').replace(/\.$/, '.0');
const hex8 = ([r, g, b, a]) => '0x' + [a, r, g, b].map((x) => Math.round(clamp(x) * 255).toString(16).padStart(2, '0')).join('').toUpperCase();

// ---------- 收集 ----------
const COLOR_GROUPS = ['text', 'bg', 'surface', 'border', 'color', 'latency', 'screen'];
const colors = [];
for (const g of COLOR_GROUPS) {
  for (const { path: p, tok } of leaves(tree[g], [g])) {
    if (g === 'latency' && p[1].startsWith('threshold')) continue;
    if (g === 'color' && p.length > 2) continue; // primitive 色板单独输出
    const dark = parseColor(resolve(tok.value));
    const light = parseColor(resolveLight(tok));
    if (!dark || !light) continue;
    colors.push({ name: camel(p), dark, light, comment: tok.comment });
  }
}
const palette = leaves(tree.color).filter((l) => l.path.length === 2).map(({ path: p, tok }) => ({ name: camel(p), c: parseColor(resolve(tok.value)) })).filter((x) => x.c);
const scalar = (group) => leaves(tree[group], [group]).map(({ path: p, tok }) => ({ name: camel(p.slice(1)), v: num(resolve(tok.value)), raw: resolve(tok.value), comment: tok.comment })).filter((x) => x.v !== null);
const space = scalar('space');
const radius = scalar('radius').map((r) => (r.v >= 9999 ? { ...r, v: 9999 } : r));
const fontSize = scalar('fontSize');
const time = scalar('time');
const easing = leaves(tree.easing, ['easing']).map(({ path: p, tok }) => ({ name: camel(p.slice(1)), b: bezier(resolve(tok.value)) })).filter((x) => x.b);
const layout = scalar('layout');
const touch = scalar('touch');
const motion = scalar('motion');
const glow = scalar('glow');
const thresholds = leaves(tree.latency).filter((l) => l.path[0].startsWith('threshold')).map(({ path: p, tok }) => ({ name: camel(p).replace(/^threshold/, '').replace(/^./, (c) => c.toLowerCase()), v: num(tok.value) }));
const glassBlur = num(resolve(tree.glass.blur.value).replace(/blur\(([\d.]+)px\)/, '$1'));
const types = Object.entries(tree.type).filter(([k]) => !k.startsWith('$')).map(([k, t]) => ({ name: camel([k]), size: num(t.size.value), weight: +t.weight.value, line: num(t.line.value), comment: t.comment }));
const ACCENTS = { blue: '#007AFF', green: '#34C759', orange: '#FF9500', pink: '#FF2D55' };

// ---------- ArkTS / 鸿蒙资源 ----------
const snake = (camelName) => camelName.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
const argb = ([r, g, b, a]) => '#' + [a, r, g, b].map((x) => Math.round(clamp(x) * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
const colorJson = (pick) => JSON.stringify({
  color: [
    ...colors.map((c) => ({ name: 'z_' + snake(c.name), value: argb(pick(c)) })),
    // 启动窗背景 = 页面底色（module.json5 startWindowBackground 引用）
    { name: 'start_window_background', value: argb(pick(colors.find((c) => c.name === 'screenBg'))) },
  ],
}, null, 2) + '\n';
const tsNum = (v) => (Number.isInteger(v) ? String(v) : String(+v.toFixed(4)));
const consts = (name, list, doc) => `${doc ? `/** ${doc} */\n` : ''}export class ${name} {\n${list.map((s) => `${s.comment ? `  /** ${s.comment} */\n` : ''}  static readonly ${s.name}: number = ${tsNum(s.v)};`).join('\n')}\n}\n`;
const ets = `// AUTO-GENERATED by apps/harmony/scripts/gen-tokens.mjs — DO NOT EDIT.
// Sources: vendor/zephyr/packages/tokens/src/*.json (desktop, read-only) + tokens/mobile.json
// 颜色不在这里：用 $r('app.color.z_<group>_<name>')，深浅色由 resources/base 与 resources/dark 自动切换。

${consts('ZSpace', space, '间距（vp）')}
${consts('ZRadius', radius, '圆角（vp）')}
${consts('ZFontSize', fontSize, '桌面字号（fp）')}
export class ZTypeStyle {
  size: number;
  weight: number;
  lineHeight: number;

  constructor(size: number, weight: number, lineHeight: number) {
    this.size = size;
    this.weight = weight;
    this.lineHeight = lineHeight;
  }
}

/** 移动端字阶：size / lineHeight 为 fp（随系统字体缩放），weight 为 100–900。 */
export class ZType {
${types.map((t) => `${t.comment ? `  /** ${t.comment} */\n` : ''}  static readonly ${t.name}: ZTypeStyle = new ZTypeStyle(${t.size}, ${t.weight}, ${t.line});`).join('\n')}
}

${consts('ZTime', time, '时长（ms）')}
/** 三次贝塞尔控制点 [x1, y1, x2, y2]，配合 curves.cubicBezierCurve(...) 使用。 */
export class ZEasing {
${easing.map((e) => `  static readonly ${e.name}: number[] = [${e.b.join(', ')}];`).join('\n')}
}

${consts('ZLayout', [...layout, ...touch.map((t) => ({ ...t, name: 'touch' + t.name.replace(/^./, (c) => c.toUpperCase()) })), { name: 'glassBlur', v: glassBlur }], '布局（vp）')}
${consts('ZMotion', [...motion.map((s) => ({ ...s, v: s.v })), { name: 'glowRadius', v: glow.find((g) => g.name === 'connect').v }, { name: 'glowAlpha', v: glow.find((g) => g.name === 'alpha').v }], '动效（带 ms 的为毫秒，其余为系数）')}
export class ZLatency {
${thresholds.map((t) => `  static readonly ${t.name}: number = ${t.v};`).join('\n')}

  /** 延迟色资源名：undefined = 未测，-1 = 超时。 */
  static colorOf(ms: number | undefined): Resource {
    if (ms === undefined) {
      return $r('app.color.z_latency_unknown');
    }
    if (ms < 0) {
      return $r('app.color.z_latency_timeout');
    }
    return ms >= ZLatency.slow ? $r('app.color.z_latency_slow') : $r('app.color.z_latency_normal');
  }
}

/** 强调色（不随深浅色变化）；紫色已废弃。 */
export enum ZAccentColor {
${Object.entries(ACCENTS).map(([k, h]) => `  ${k.toUpperCase()} = '${argb(parseColor(h))}'`).join(',\n')}
}
`;

const outs = {
  [path.join(app, 'entry/src/main/resources/base/element/color.json')]: colorJson((c) => c.light),
  [path.join(app, 'entry/src/main/resources/dark/element/color.json')]: colorJson((c) => c.dark),
  [path.join(app, 'entry/src/main/ets/generated/ZTokens.ets')]: ets,
};
let dirty = false;
for (const [f, s] of Object.entries(outs)) {
  if (check) {
    if (!fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== s) { console.error(`过期：${path.relative(root, f)}`); dirty = true; }
  } else {
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, s);
    console.log(`写出 ${path.relative(root, f)}（${s.split('\n').length} 行）`);
  }
}
console.log(`colors ${colors.length} · space ${space.length} · radius ${radius.length} · type ${types.length}`);
process.exit(dirty ? 1 : 0);
