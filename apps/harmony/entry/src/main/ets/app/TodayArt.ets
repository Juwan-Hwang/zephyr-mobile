/*
 * 今日卡的纯逻辑（M1-9 / U13，对照 Android ui/today/TodayScreen.kt Flow / TodayStyle、iOS Activity/TodayCard + WindArt）：
 * - 三配色 夜 / 晨 / 雾（底色、线色、字色）。
 * - 流场：约 140 条线，振幅跟随 24 小时流量；同一天的数据画出同一张图（无随机数）。不含节点名与 IP。
 * - 统计：地区数、在线小时（向下取整）、最快延迟（无则 “—”）。
 * 不依赖 ArkUI，node / ohosTest 可测；页面用 Canvas 按这里的点画线。
 */
import { UsageSummary } from '../engine/Model';

export enum TodayStyle {
  NIGHT = 'night',
  DAWN = 'dawn',
  MIST = 'mist'
}

export const TODAY_STYLES: TodayStyle[] = [TodayStyle.NIGHT, TodayStyle.DAWN, TodayStyle.MIST];
export const TODAY_STRANDS: number = 140;
export const TODAY_STEP_PX: number = 6;
/** 卡片宽高比（Android aspectRatio(0.68f)）。 */
export const TODAY_ASPECT: number = 0.68;

export class TodayPalette {
  bg: string;
  line: string;
  fg: string;

  constructor(bg: string, line: string, fg: string) {
    this.bg = bg;
    this.line = line;
    this.fg = fg;
  }
}

export class TodayStats {
  regions: number;
  hours: number;
  /** 最快延迟文字；没有时 “—”。 */
  fastest: string;

  constructor(regions: number, hours: number, fastest: string) {
    this.regions = regions;
    this.hours = hours;
    this.fastest = fastest;
  }
}

export class TodayArt {
  static palette(s: TodayStyle): TodayPalette {
    switch (s) {
      case TodayStyle.DAWN:
        return new TodayPalette('#F6EEE6', '#E07A4F', '#1B1B1F');
      case TodayStyle.MIST:
        return new TodayPalette('#ECEDEF', '#6C8DB8', '#1B1B1F');
      default:
        return new TodayPalette('#02040A', '#3BA4FF', '#FFFFFF');
    }
  }

  /** '#RRGGBB' + 透明度 0–1 → '#AARRGGBB'（ArkUI / Canvas 颜色）。 */
  static withAlpha(hex: string, a: number): string {
    const v = Math.round(Math.min(1, Math.max(0, a)) * 255);
    const h = v.toString(16).toUpperCase();
    return '#' + (h.length < 2 ? '0' + h : h) + hex.substring(1);
  }

  static maxHourly(hourly: number[]): number {
    let m = 1;
    for (const v of hourly) {
      m = Math.max(m, v);
    }
    return m;
  }

  /** 第 s 条线在 x 处的 y（同 Android Flow：baseY − sin(...)·h·0.18·(0.4 + amp) + t·x·0.12）。 */
  static y(hourly: number[], max: number, w: number, h: number, s: number, x: number, phase: number): number {
    const t = s / TODAY_STRANDS;
    const baseY = h * (0.12 + 0.55 * t);
    const hour = Math.min(23, Math.max(0, Math.floor((x / w) * 23)));
    const amp = (hour < hourly.length ? hourly[hour] : 0) / max;
    return baseY - Math.sin((x / w) * Math.PI * 1.1 + t * 2.4 + phase) * h * 0.18 * (0.4 + amp) + t * x * 0.12;
  }

  /** 第 s 条线的透明度：中间（t≈0.45）最亮。 */
  static alpha(s: number): number {
    const t = s / TODAY_STRANDS;
    return 0.05 + 0.35 * Math.max(0, 1 - Math.abs(t - 0.45) * 2);
  }

  /** 一条线的点（x 每 6px 一步，含 0 与 ≤ w 的末点）。 */
  static strand(hourly: number[], w: number, h: number, s: number, phase: number): number[] {
    const max = TodayArt.maxHourly(hourly);
    const pts: number[] = [];
    for (let x = 0; x <= w; x += TODAY_STEP_PX) {
      pts.push(x, TodayArt.y(hourly, max, w, h, s, x, phase));
    }
    return pts;
  }

  static stats(u: UsageSummary | undefined): TodayStats {
    if (u === undefined) {
      return new TodayStats(0, 0, '—');
    }
    return new TodayStats(u.regionsToday, Math.floor(u.onlineMillisToday / 3600000),
      u.fastestLatencyMs !== undefined ? String(u.fastestLatencyMs) : '—');
  }

  /** 存图 / 分享的文件名。 */
  static fileName(now: number): string {
    return 'Zephyr-' + String(now) + '.png';
  }
}
