/*
 * 数字 / 时间格式化（对照 Android design ZFormat、iOS ZFormat）。纯函数、不碰资源，便于 tsc 与 node 测试；
 * 带文字的部分（“5 分钟前”“已过期”）只给出结构化结果（AgoParts / ExpiryParts），由 common/Labels 映射到字符串资源。
 *
 * 契约 §16.e ①（U21）：十进制单位（1 KB = 1000 B），四舍五入（half-up），进位后满 1000 升一级。
 * - 字节：B / KB 取整；MB 小于 100 一位小数、满 100 取整；GB / TB 一位小数。999.6 KB → "1.0 MB"。
 * - 速率：B/s、KB/s 取整；MB/s、GB/s 一位小数。194600 → "195 KB/s"，2849999 → "2.8 MB/s"。
 * 全程整数运算（除数 = 1000^unit / 10^小数位，必为整数），2^53 内精确，不受浮点舍入影响。
 */
import { LATENCY_TIMEOUT } from '../engine/Model';

const BYTE_UNITS: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
const RATE_UNITS: string[] = ['B', 'KB', 'MB', 'GB'];

/** 数值与单位分开（统计卡大字 + 小单位）。 */
export interface ValueUnit {
  value: string;
  unit: string;
}

/** 毫秒延迟的显示档位，对应颜色令牌 latency_normal / latency_slow / latency_timeout / latency_unknown。 */
export enum LatencyClass {
  NORMAL = 'normal',
  SLOW = 'slow',
  TIMEOUT = 'timeout',
  UNKNOWN = 'unknown'
}

/** 相对过去时间的档位：now = 刚刚，其余带数量。 */
export enum AgoUnit {
  NOW = 'now',
  MINUTES = 'minutes',
  HOURS = 'hours',
  DAYS = 'days'
}

export interface AgoParts {
  unit: AgoUnit;
  count: number;
}

export enum ExpiryKind {
  EXPIRED = 'expired',
  TODAY = 'today',
  DAYS = 'days'
}

export interface ExpiryParts {
  kind: ExpiryKind;
  /** 距到期的日历天数（本地时区），kind = DAYS 时 ≥ 1。 */
  days: number;
}

/** 延迟 ≥ 此值显示为“慢”（设计令牌 latencySlow 注释：>= 200ms）。 */
export const SLOW_LATENCY_MS: number = 200;

function pow1000(n: number): number {
  let r = 1;
  for (let i = 0; i < n; i++) {
    r *= 1000;
  }
  return r;
}

/** raw / div 四舍五入（half-up），raw、div 为非负整数。 */
function roundDiv(raw: number, div: number): number {
  const q = Math.floor(raw / div);
  const rem = raw - q * div;
  return rem * 2 >= div ? q + 1 : q;
}

/** 整数 r 表示 value × 10^decimals，转成 "12.3" / "195"。 */
function fixed(r: number, decimals: number): string {
  if (decimals === 0) {
    return String(r);
  }
  const whole = Math.floor(r / 10);
  return String(whole) + '.' + String(r - whole * 10);
}

type DecimalsFn = (unit: number, raw: number) => number;

function scaled(n: number, units: string[], decimals: DecimalsFn): ValueUnit {
  const raw = Math.round(Math.abs(n));
  let unit = 0;
  while (unit < units.length - 1 && raw >= pow1000(unit + 1)) {
    unit++;
  }
  for (;;) {
    const d = unit === 0 ? 0 : decimals(unit, raw);
    const scale = d === 0 ? 1 : 10;
    const r = roundDiv(raw, pow1000(unit) / scale);
    if (r >= 1000 * scale && unit < units.length - 1) {
      unit++;
      continue;
    }
    const out: ValueUnit = { value: fixed(r, d), unit: units[unit] };
    return out;
  }
}

function byteDecimals(unit: number, raw: number): number {
  if (unit <= 1) {
    return 0;
  }
  if (unit === 2) {
    // MB：先按一位小数舍入，满 100.0 改取整（99.95 MB → "100 MB"）。
    return roundDiv(raw, pow1000(2) / 10) >= 1000 ? 0 : 1;
  }
  return 1;
}

function rateDecimals(unit: number, raw: number): number {
  return unit <= 1 ? 0 : 1;
}

export class Format {
  /** 字节：("12.3", "MB")。 */
  static bytes(b: number): ValueUnit {
    return scaled(b, BYTE_UNITS, byteDecimals);
  }

  /** "12.3 MB"。 */
  static bytesText(b: number): string {
    const v = Format.bytes(b);
    return v.value + ' ' + v.unit;
  }

  /** 速率：("2.8", "MB")，单位不带 "/s"。 */
  static rate(bps: number): ValueUnit {
    return scaled(bps, RATE_UNITS, rateDecimals);
  }

  /** "2.8 MB/s"。 */
  static rateText(bps: number): string {
    const v = Format.rate(bps);
    return v.value + ' ' + v.unit + '/s';
  }

  /** 13109802 → "13,109,802"（数字一律拉丁、逗号分组，与 Android grouped 相同）。 */
  static grouped(n: number): string {
    const neg = n < 0;
    const s = String(Math.floor(Math.abs(n)));
    let out = '';
    for (let i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 === 0) {
        out += ',';
      }
      out += s.charAt(i);
    }
    return neg ? '-' + out : out;
  }

  /**
   * 地区 chip 的节点数（同 Android ZFormat.chip）：用“万”的语言（hm_number_myriad = true，同 Android common_number_myriad）
   * 读 “12 万”；其余为短紧凑写法 1.2K / 12K / 3.4M（CompactDecimalFormat SHORT，两位有效数字、整数位不截）。
   */
  static chip(n: number, myriad: boolean, wan: string): string {
    if (myriad) {
      return String(Math.round(n / 1e4)) + ' ' + wan;
    }
    const units: string[] = ['', 'K', 'M', 'B', 'T'];
    let u = 0;
    let v = Math.abs(n);
    while (v >= 1000 && u < units.length - 1) {
      v = v / 1000;
      u++;
    }
    let r = v < 10 && u > 0 ? Math.round(v * 10) / 10 : Math.round(v);
    if (r >= 1000 && u < units.length - 1) {
      r = 1;
      u++;
    }
    return (n < 0 ? '-' : '') + String(r) + units[u];
  }

  /** 8047000 → "2:14:07"；不足一小时 "0:04:07"。 */
  static duration(ms: number): string {
    const s = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    return String(h) + ':' + Format.pad2(m) + ':' + Format.pad2(sec);
  }

  /** 微秒耗时：< 1 ms 两位小数，否则一位："0.42 ms" / "12.3 ms"。 */
  static micros(us: number): string {
    const ms = us / 1000;
    return (us < 1000 ? ms.toFixed(2) : ms.toFixed(1)) + ' ms';
  }

  /** 延迟数字（不含单位）："38"；超时 / 未测返回 undefined，由 Labels 给文案或占位。 */
  static latencyValue(ms: number | undefined): string | undefined {
    if (ms === undefined || ms < 0) {
      return undefined;
    }
    return String(Math.round(ms));
  }

  /** "38 ms"；超时 / 未测为空串。 */
  static latencyMsText(ms: number | undefined): string {
    const v = Format.latencyValue(ms);
    return v === undefined ? '' : v + ' ms';
  }

  static latencyClass(ms: number | undefined): LatencyClass {
    if (ms === undefined) {
      return LatencyClass.UNKNOWN;
    }
    if (ms === LATENCY_TIMEOUT || ms < 0) {
      return LatencyClass.TIMEOUT;
    }
    return ms >= SLOW_LATENCY_MS ? LatencyClass.SLOW : LatencyClass.NORMAL;
  }

  /** 相对过去时间：< 1 分钟 = 刚刚；未来时间按刚刚。 */
  static ago(at: number, now: number): AgoParts {
    const d = Math.floor(Math.max(0, now - at) / 1000);
    let p: AgoParts;
    if (d < 60) {
      p = { unit: AgoUnit.NOW, count: 0 };
    } else if (d < 3600) {
      p = { unit: AgoUnit.MINUTES, count: Math.floor(d / 60) };
    } else if (d < 86400) {
      p = { unit: AgoUnit.HOURS, count: Math.floor(d / 3600) };
    } else {
      p = { unit: AgoUnit.DAYS, count: Math.floor(d / 86400) };
    }
    return p;
  }

  /** 本地时区的日历日序号（跨夏令时也按日历日算）。 */
  static localDay(at: number): number {
    const d = new Date(at);
    return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
  }

  /** §16.e ③ 到期：已过 / 今天 / N 天后（本地日历日，23:00 → 次日 01:00 算 1 天）。 */
  static expiry(at: number, now: number): ExpiryParts {
    let p: ExpiryParts;
    if (at <= now) {
      p = { kind: ExpiryKind.EXPIRED, days: 0 };
      return p;
    }
    const days = Format.localDay(at) - Format.localDay(now);
    p = days <= 0 ? { kind: ExpiryKind.TODAY, days: 0 } : { kind: ExpiryKind.DAYS, days: days };
    return p;
  }

  /** "2026-11-20"（本地时区）。 */
  static date(at: number): string {
    const d = new Date(at);
    return String(d.getFullYear()) + '-' + Format.pad2(d.getMonth() + 1) + '-' + Format.pad2(d.getDate());
  }

  /** "18:41:07"（本地时区，日志行）。 */
  static time(at: number): string {
    const d = new Date(at);
    return Format.pad2(d.getHours()) + ':' + Format.pad2(d.getMinutes()) + ':' + Format.pad2(d.getSeconds());
  }

  /** 已用 / 总量的比例，0–1；总量缺失或为 0 时 undefined。 */
  static ratio(used: number | undefined, total: number | undefined): number | undefined {
    if (used === undefined || total === undefined || total <= 0) {
      return undefined;
    }
    return Math.max(0, Math.min(1, used / total));
  }

  static pad2(n: number): string {
    return n < 10 ? '0' + String(n) : String(n);
  }
}
