#!/usr/bin/env node
// Zephyr Mobile token 生成器（零依赖）。
// 输入：vendor/zephyr/packages/tokens/src/{primitive,semantic,component}.json（桌面，只读）+ tokens/mobile.json（移动增补）
// 输出：tokens/generated/ios/ZTokens.swift、tokens/generated/android/ZTokens.kt
// 颜色输出为 light/dark 动态色：iOS 用 UIColor(dynamicProvider:)，Android 用 ZColors 两套实例 + CompositionLocal。组件里不写三元判断。
// 用法：node tokens/build.mjs [--check]   （--check：产物与仓库不一致则退出 1，CI 用）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const desktopDir = path.join(root, 'vendor/zephyr/packages/tokens/src');
const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

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

const header = (lang) => `${lang === 'swift' ? '//' : '//'} AUTO-GENERATED by tokens/build.mjs — DO NOT EDIT.
// Sources: vendor/zephyr/packages/tokens/src/*.json (desktop, read-only) + tokens/mobile.json
`;

// ---------- Swift ----------
const swW = (w) => ({ 100: '.ultraLight', 200: '.thin', 300: '.light', 400: '.regular', 500: '.medium', 600: '.semibold', 700: '.bold', 800: '.heavy', 900: '.black' })[w] || '.regular';
const swRGBA = ([r, g, b, a]) => `UIColor(red: ${f3(r)}, green: ${f3(g)}, blue: ${f3(b)}, alpha: ${f3(a)})`;
const swift = `${header('swift')}
import SwiftUI
import UIKit

public enum ZTokens {
    /// 动态色：自动跟随 light/dark。
    public enum Colors {
${colors.map((c) => `${c.comment ? `        /// ${c.comment}\n` : ''}        public static let ${c.name} = ZDynamicColor.make(dark: ${swRGBA(c.dark)}, light: ${swRGBA(c.light)})`).join('\n')}
    }

    /// 静态色板（不随外观变化）。
    public enum Palette {
${palette.map((p) => `        public static let ${p.name} = Color(.sRGB, red: ${f3(p.c[0])}, green: ${f3(p.c[1])}, blue: ${f3(p.c[2])}, opacity: ${f3(p.c[3])})`).join('\n')}
    }

    public enum Accent: String, CaseIterable, Sendable {
${Object.keys(ACCENTS).map((k) => `        case ${k}`).join('\n')}
        public var color: Color {
            switch self {
${Object.entries(ACCENTS).map(([k, h]) => { const c = parseColor(h); return `            case .${k}: return Color(.sRGB, red: ${f3(c[0])}, green: ${f3(c[1])}, blue: ${f3(c[2])})`; }).join('\n')}
            }
        }
        public var glow: Color { color.opacity(0.2) }
    }

    public enum Space {
${space.map((s) => `        public static let ${s.name}: CGFloat = ${s.v}`).join('\n')}
    }

    public enum Radius {
${radius.map((s) => `        public static let ${s.name}: CGFloat = ${s.v}`).join('\n')}
    }

    public enum FontSize {
${fontSize.map((s) => `        public static let ${s.name}: CGFloat = ${s.v}`).join('\n')}
    }

    /// 移动端字阶。size 为 pt，配合 Dynamic Type：用 \`ZTokens.TypeStyle.body.font\`（relativeTo 对应文本样式缩放）。
    public struct TypeStyle: Sendable {
        public let size: CGFloat
        public let weight: Font.Weight
        public let lineHeight: CGFloat
        public let relativeTo: Font.TextStyle
        /// 固定大小（不随 Dynamic Type）。正文请用 \`.zType(_:)\` 修饰符，它会按 relativeTo 缩放。
        public var font: Font { .system(size: size, weight: weight) }
${types.map((t) => `${t.comment ? `        /// ${t.comment}\n` : ''}        public static let ${t.name} = TypeStyle(size: ${t.size}, weight: ${swW(t.weight)}, lineHeight: ${t.line}, relativeTo: ${({ caption: '.caption', footnote: '.footnote', button: '.body', body: '.body', headline: '.headline', title: '.title2', large: '.largeTitle', metric: '.largeTitle', metricSm: '.title2' })[t.name] || '.body'})`).join('\n')}
    }

    public enum Time {
${time.map((s) => `        public static let ${s.name}: Double = ${s.v / 1000}  // s`).join('\n')}
    }

    public enum Easing {
${easing.map((e) => `        public static let ${e.name} = Animation.timingCurve(${e.b.join(', ')}, duration: Time.standard)
        public static func ${e.name}(duration: Double) -> Animation { .timingCurve(${e.b.join(', ')}, duration: duration) }`).join('\n')}
    }

    public enum Layout {
${[...layout, ...touch.map((t) => ({ ...t, name: 'touch' + t.name.replace(/^./, (c) => c.toUpperCase()) }))].map((s) => `${s.comment ? `        /// ${s.comment}\n` : ''}        public static let ${s.name}: CGFloat = ${s.v}`).join('\n')}
        public static let glassBlur: CGFloat = ${glassBlur}
    }

    public enum Motion {
${motion.map((s) => `${s.comment ? `        /// ${s.comment}\n` : ''}        public static let ${s.name}: Double = ${/ms|s$/.test(s.raw) ? s.v / 1000 : s.v}`).join('\n')}
        public static let spring = Animation.spring(response: springResponse, dampingFraction: springDamping)
        public static let glowRadius: CGFloat = ${glow.find((g) => g.name === 'connect').v}
        public static let glowAlpha: Double = ${glow.find((g) => g.name === 'alpha').v}
    }

    public enum LatencyThreshold {
${thresholds.map((t) => `        public static let ${t.name}: Int = ${t.v}`).join('\n')}
        /// nil = 未测，-1 = 超时
        public static func color(_ ms: Int?) -> Color {
            guard let ms else { return Colors.latencyUnknown }
            if ms < 0 { return Colors.latencyTimeout }
            return ms >= slow ? Colors.latencySlow : Colors.latencyNormal
        }
    }
}

public enum ZDynamicColor {
    public static func make(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? light : dark })
    }
}

/// 随 Dynamic Type 缩放的字阶；metric 类自动等宽数字。
public struct ZTypeModifier: ViewModifier {
    private let style: ZTokens.TypeStyle
    private let monospacedDigits: Bool
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var lineHeight: CGFloat
    public init(_ style: ZTokens.TypeStyle, monospacedDigits: Bool = false) {
        self.style = style
        self.monospacedDigits = monospacedDigits
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        _lineHeight = ScaledMetric(wrappedValue: style.lineHeight, relativeTo: style.relativeTo)
    }
    public func body(content: Content) -> some View {
        let f = Font.system(size: size, weight: style.weight)
        content
            .font(monospacedDigits ? f.monospacedDigit() : f)
            .lineSpacing(max(0, lineHeight - size * 1.2))
    }
}

public extension View {
    func zType(_ style: ZTokens.TypeStyle, monospacedDigits: Bool? = nil) -> some View {
        modifier(ZTypeModifier(style, monospacedDigits: monospacedDigits ?? (style.weight == .ultraLight || style.weight == .thin || style.weight == .light)))
    }
}
`;

// ---------- Kotlin ----------
const ktW = (w) => `FontWeight.W${w}`;
const kotlin = `${header('kt')}
@file:Suppress("unused", "MagicNumber")

package com.zephyr.design.tokens

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFeature
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 动态色：深色与浅色两套实例，经 [LocalZColors] 提供。组件只读 LocalZColors.current，不写三元判断。 */
@Immutable
data class ZColors(
${colors.map((c) => `    val ${c.name}: Color,`).join('\n')}
    val isDark: Boolean,
) {
    companion object {
        val Dark = ZColors(
${colors.map((c) => `            ${c.name} = Color(${hex8(c.dark)}),`).join('\n')}
            isDark = true,
        )
        val Light = ZColors(
${colors.map((c) => `            ${c.name} = Color(${hex8(c.light)}),`).join('\n')}
            isDark = false,
        )
    }
}

val LocalZColors = staticCompositionLocalOf { ZColors.Dark }

object ZPalette {
${palette.map((p) => `    val ${p.name} = Color(${hex8(p.c)})`).join('\n')}
}

enum class ZAccent(val color: Color) {
${Object.entries(ACCENTS).map(([k, h]) => `    ${k.toUpperCase()}(Color(${hex8(parseColor(h))})),`).join('\n')}
    ;
    val glow: Color get() = color.copy(alpha = 0.2f)
}

object ZSpace {
${space.map((s) => `    val ${s.name} = ${s.v}.dp`).join('\n')}
}

object ZRadius {
${radius.map((s) => `    val ${s.name} = ${s.v}.dp`).join('\n')}
}

object ZFontSize {
${fontSize.map((s) => `    val ${s.name} = ${s.v}.sp`).join('\n')}
}

/** 移动端字阶（sp 自动跟随系统 fontScale）。数字类样式启用等宽数字 tnum。 */
object ZType {
${types.map((t) => `${t.comment ? `    /** ${t.comment} */\n` : ''}    val ${t.name} = TextStyle(fontSize = ${t.size}.sp, fontWeight = ${ktW(t.weight)}, lineHeight = ${t.line}.sp${t.name.startsWith('metric') ? ', fontFeatureSettings = "tnum"' : ''})`).join('\n')}
}

object ZTime {
${time.map((s) => `    const val ${s.name}: Int = ${s.v}  // ms`).join('\n')}
}

object ZEasing {
${easing.map((e) => `    val ${e.name} = CubicBezierEasing(${e.b.map((x) => `${x}f`).join(', ')})`).join('\n')}
}

object ZLayout {
${[...layout, ...touch.map((t) => ({ ...t, name: 'touch' + t.name.replace(/^./, (c) => c.toUpperCase()) }))].map((s) => `${s.comment ? `    /** ${s.comment} */\n` : ''}    val ${s.name} = ${s.v}.dp`).join('\n')}
    val glassBlur = ${glassBlur}.dp
}

object ZMotion {
${motion.map((s) => `${s.comment ? `    /** ${s.comment} */\n` : ''}    const val ${s.name}: Float = ${/ms|s$/.test(s.raw) ? s.v : s.v}f${/ms|s$/.test(s.raw) ? '  // ms' : ''}`).join('\n')}
    /** SwiftUI spring(response, damping) 换算为 Compose spring：stiffness = (2π / response)²，dampingRatio = damping */
    val springStiffness: Float = ((2 * Math.PI / springResponse) * (2 * Math.PI / springResponse)).toFloat()
    val springDampingRatio: Float = springDamping
    val glowRadius = ${glow.find((g) => g.name === 'connect').v}.dp
    const val glowAlpha: Float = ${glow.find((g) => g.name === 'alpha').v}f
}

object ZLatency {
${thresholds.map((t) => `    const val ${t.name}: Int = ${t.v}`).join('\n')}
    /** null = 未测，-1 = 超时 */
    fun color(ms: Int?, c: ZColors): Color = when {
        ms == null -> c.latencyUnknown
        ms < 0 -> c.latencyTimeout
        ms >= slow -> c.latencySlow
        else -> c.latencyNormal
    }
}
`;

// ---------- 写出 ----------
const outs = {
  [path.join(here, 'generated/ios/ZTokens.swift')]: swift,
  [path.join(here, 'generated/android/ZTokens.kt')]: kotlin.replace('import androidx.compose.ui.text.font.FontFeature\n', ''),
};
const check = process.argv.includes('--check');
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
console.log(`colors ${colors.length} · palette ${palette.length} · space ${space.length} · radius ${radius.length} · type ${types.length}`);
process.exit(dirty ? 1 : 0);
