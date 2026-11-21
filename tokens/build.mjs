#!/usr/bin/env node
// Zephyr Mobile token 生成器（零依赖）。
// 输入：vendor/zephyr/packages/tokens/src/{primitive,semantic,component}.json（桌面，只读）+ tokens/mobile.json（移动增补）
// 输出：tokens/generated/ios/ZTokens.swift、tokens/generated/android/ZTokens.kt、tokens/generated/harmony/{ZTokens.ets,resources/*/element/color.json}
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
// 强调色（mobile.json accent.<name>.{base,text,fill,on-fill}，value = 深色、lightValue = 浅色）。
// ACCENTS = 浅色 base，即历史上的单一值（ZTokens.Accent.color / ZAccent.color 不变，避免基线漂移）；新增的深浅色变体见 ACCENT_SET。
const ACCENT_ROLES = ['base', 'text', 'fill', 'on-fill'];
const ACCENT_SET = Object.fromEntries(Object.entries(tree.accent).filter(([k]) => !k.startsWith('$')).map(([k, v]) => [k, Object.fromEntries(ACCENT_ROLES.map((r) => {
  if (!v[r]) throw new Error(`mobile.json accent.${k} 缺 ${r}`);
  return [r, { dark: parseColor(resolve(v[r].value)), light: parseColor(resolveLight(v[r])) }];
}))]));
const ACCENTS = Object.fromEntries(Object.entries(tree.accent).filter(([k]) => !k.startsWith('$')).map(([k, v]) => [k, resolveLight(v.base)]));

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
${[['adaptive', 'base', '跟随深浅色的强调色（深色用更亮的系统深色变体）：开关、进度、光晕、选中描边等填充与大图形'], ['text', 'text', '前景小字 / 链接 / 索引条 / 搜索高亮 / 图标（浅色加深，过 WCAG 正文 4.5）'], ['fill', 'fill', '主按钮 / 选中胶囊的底，与 onFill 配对'], ['onFill', 'on-fill', 'fill 上的文字（green / orange 为黑字）']].map(([n, r, doc]) => `        /// ${doc}
        public var ${n}: Color {
            switch self {
${Object.entries(ACCENT_SET).map(([k, v]) => `            case .${k}: return ZDynamicColor.make(dark: ${swRGBA(v[r].dark)}, light: ${swRGBA(v[r].light)})`).join('\n')}
            }
        }`).join('\n')}
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

/**
 * 用户可选强调色。[color] = 浅色 base（历史单一值，保持不变）；深浅色变体：
 * [base] 开关 / 进度 / 光晕等填充（深色即原 ZColors.kt 的 darkVariant），[text] 前景小字 / 链接 / 图标（浅色加深过 4.5），
 * [fill] + [onFill] 主按钮 / 选中胶囊（green / orange 为黑字）。传 ZColors.isDark。
 */
enum class ZAccent(
    val color: Color,
    val colorDark: Color,
    val textLight: Color,
    val textDark: Color,
    val fillLight: Color,
    val fillDark: Color,
    val onFillLight: Color,
    val onFillDark: Color,
) {
${Object.entries(ACCENT_SET).map(([k, v]) => `    ${k.toUpperCase()}(Color(${hex8(parseColor(ACCENTS[k]))}), Color(${hex8(v.base.dark)}), Color(${hex8(v.text.light)}), Color(${hex8(v.text.dark)}), Color(${hex8(v.fill.light)}), Color(${hex8(v.fill.dark)}), Color(${hex8(v['on-fill'].light)}), Color(${hex8(v['on-fill'].dark)})),`).join('\n')}
    ;
    val glow: Color get() = color.copy(alpha = 0.2f)
    fun base(dark: Boolean): Color = if (dark) colorDark else color
    fun text(dark: Boolean): Color = if (dark) textDark else textLight
    fun fill(dark: Boolean): Color = if (dark) fillDark else fillLight
    fun onFill(dark: Boolean): Color = if (dark) onFillDark else onFillLight
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


// ---------- ArkTS（HarmonyOS，apps/harmony 由 D 引用） ----------
// 两种产物：ZTokens.ets（常量，深浅两套色对象）与资源 color.json（base=浅色、dark=深色，系统按深浅色自动切换，用 $r('app.color.xxx')）。
const argb = (c) => '#' + hex8(c).slice(2);
const snake = (n) => n.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
const etsAccLit = (v, m) => `{ base: '${argb(v.base[m])}', text: '${argb(v.text[m])}', fill: '${argb(v.fill[m])}', onFill: '${argb(v['on-fill'][m])}' }`;
const etsAcc = (v) => `if (isDark) {
        const d: ZAccentColors = ${etsAccLit(v, 'dark')};
        return d;
      }
      const l: ZAccentColors = ${etsAccLit(v, 'light')};
      return l;`;
const etsObj = (name, pick) => `export const ${name}: ZColors = {
${colors.map((c) => `  ${c.name}: '${argb(pick(c))}',`).join('\n')}
};`;
const arkts = `${header('ets')}
// 用法：颜色优先用资源 $r('app.color.<snake_name>')（自动跟随深浅色）；需要在代码里取值时用 zColors(isDark)。
// 尺寸单位为 vp（字号 fp），时间为 ms。

export interface ZColors {
${colors.map((c) => `${c.comment ? `  /** ${c.comment} */\n` : ''}  ${c.name}: string;`).join('\n')}
}

${etsObj('ZColorsDark', (c) => c.dark)}

${etsObj('ZColorsLight', (c) => c.light)}

export function zColors(isDark: boolean): ZColors {
  return isDark ? ZColorsDark : ZColorsLight;
}

export class ZPalette {
${palette.map((p) => `  static readonly ${p.name}: string = '${argb(p.c)}';`).join('\n')}
}

export enum ZAccent {
${Object.entries(ACCENTS).map(([k, h]) => `  ${k.toUpperCase()} = '${argb(parseColor(h))}',`).join('\n')}
}

/** 强调色深浅色变体（资源里也有 accent_<name>[_text|_fill|_on_fill]，随深浅色自动切换）。 */
export interface ZAccentColors {
  /** 开关 / 进度 / 光晕等填充与大图形 */
  base: string;
  /** 前景小字 / 链接 / 图标（浅色加深，过正文 4.5） */
  text: string;
  /** 主按钮 / 选中胶囊的底 */
  fill: string;
  /** fill 上的文字 */
  onFill: string;
}

/** name：'blue' | 'green' | 'orange' | 'pink'；未知名按 blue。 */
export function zAccentColors(name: string, isDark: boolean): ZAccentColors {
  switch (name) {
${Object.entries(ACCENT_SET).filter(([k]) => k !== 'blue').map(([k, v]) => `    case '${k}': {
      ${etsAcc(v)}
    }`).join('\n')}
    default: {
      ${etsAcc(ACCENT_SET.blue)}
    }
  }
}

export class ZSpace {
${space.map((s) => `  static readonly ${s.name}: number = ${s.v};`).join('\n')}
}

export class ZRadius {
${radius.map((s) => `  static readonly ${s.name}: number = ${s.v};`).join('\n')}
}

export class ZFontSize {
${fontSize.map((s) => `  static readonly ${s.name}: number = ${s.v};`).join('\n')}
}

export interface ZTypeStyle {
  size: number;
  weight: number;
  lineHeight: number;
  tabularNums: boolean;
}

export class ZType {
${types.map((t) => `${t.comment ? `  /** ${t.comment} */\n` : ''}  static readonly ${t.name}: ZTypeStyle = { size: ${t.size}, weight: ${t.weight}, lineHeight: ${t.line}, tabularNums: ${t.name.startsWith('metric')} };`).join('\n')}
}

export class ZTime {
${time.map((s) => `  static readonly ${s.name}: number = ${s.v};`).join('\n')}
}

/** cubic-bezier 控制点，配合 curves.cubicBezierCurve(...ZEasing.x)。 */
export class ZEasing {
${easing.map((e) => `  static readonly ${e.name}: number[] = [${e.b.join(', ')}];`).join('\n')}
}

export class ZLayout {
${[...layout, ...touch.map((t) => ({ ...t, name: 'touch' + t.name.replace(/^./, (c) => c.toUpperCase()) }))].map((s) => `${s.comment ? `  /** ${s.comment} */\n` : ''}  static readonly ${s.name}: number = ${s.v};`).join('\n')}
  static readonly glassBlur: number = ${glassBlur};
}

export class ZMotion {
${motion.map((s) => `${s.comment ? `  /** ${s.comment} */\n` : ''}  static readonly ${s.name}: number = ${s.v};${/ms|s$/.test(s.raw) ? '  // ms' : ''}`).join('\n')}
  /** SwiftUI spring(response, damping) 换算：stiffness = (2π / response)²，damping 比例同值，供 curves.springMotion / interpolatingSpring 换算用。 */
  static readonly springStiffness: number = Math.pow(2 * Math.PI / ${motion.find((m) => m.name === 'springResponse')?.v ?? 0.5}, 2);
  static readonly glowRadius: number = ${glow.find((g) => g.name === 'connect').v};
  static readonly glowAlpha: number = ${glow.find((g) => g.name === 'alpha').v};
}

export class ZLatency {
${thresholds.map((t) => `  static readonly ${t.name}: number = ${t.v};`).join('\n')}
  /** undefined = 未测，-1 = 超时 */
  static color(ms: number | undefined, c: ZColors): string {
    if (ms === undefined) return c.latencyUnknown;
    if (ms < 0) return c.latencyTimeout;
    return ms >= ZLatency.slow ? c.latencySlow : c.latencyNormal;
  }
}
`;
const accentRes = Object.entries(ACCENT_SET).flatMap(([k, v]) => ACCENT_ROLES.map((r) => ({ name: `accent_${k}${r === 'base' ? '' : '_' + r.replace('-', '_')}`, ...v[r] })));
const colorRes = (pick) => JSON.stringify({ color: [...colors, ...accentRes].map((c) => ({ name: snake(c.name), value: argb(pick(c)) })) }, null, 2) + '\n';

// ---------- 写出 ----------
const outs = {
  [path.join(here, 'generated/ios/ZTokens.swift')]: swift,
  [path.join(here, 'generated/harmony/ZTokens.ets')]: arkts,
  [path.join(here, 'generated/harmony/resources/base/element/color.json')]: colorRes((c) => c.light),
  [path.join(here, 'generated/harmony/resources/dark/element/color.json')]: colorRes((c) => c.dark),
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
