/*
 * 设置 › 诊断 › 日志（对照 Android LogsModel）：订阅 engine.logs()，按所选级别过滤，保留最新 CAPACITY 行。
 * - §16.h：选 debug 时 engine.setLogLevel('debug')，离开日志页（stop）或改回其它级别时回 info。
 *   warning / error 只过滤显示，info 历史保留。
 * - 暂停只停止追加；清空只清本地缓冲。
 * 进程内单例（AppServices.logs）：设置页的“日志级别”与日志页共用同一级别。
 */
import { LogLevel, logLevelRank, LogLine, Settings } from '../engine/Model';
import { SettingsCodec } from '../engine/SettingsCodec';
import { StateStream, Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export const LOG_CAPACITY: number = 500;
export const RECENT_ERRORS_MAX: number = 20;

export interface DiagError {
  at: number;
  /** ErrorCode 名，如 SUBSCRIPTION_FETCH_FAILED。 */
  code: string;
}

function pad(n: number, w: number): string {
  let s = String(n);
  while (s.length < w) {
    s = '0' + s;
  }
  return s;
}

export class LogsModel {
  private engine: ZephyrEngine;
  private sub: StreamSub | undefined = undefined;
  private buffer: LogLine[] = [];
  readonly lines: StateStream<LogLine[]> = new StateStream<LogLine[]>([]);
  readonly level: StateStream<LogLevel> = new StateStream<LogLevel>(LogLevel.INFO);
  readonly paused: StateStream<boolean> = new StateStream<boolean>(false);

  constructor(engine: ZephyrEngine) {
    this.engine = engine;
  }

  get running(): boolean {
    return this.sub !== undefined;
  }

  /** 日志页出现时调用。 */
  start(): void {
    if (this.sub !== undefined) {
      return;
    }
    if (this.level.value === LogLevel.DEBUG) {
      this.engine.setLogLevel(LogLevel.DEBUG).catch(() => {});
    }
    this.sub = this.engine.logs().subscribe((l: LogLine) => this.append(l));
  }

  /** 日志页消失时调用：§16.h 把内核放回 info。 */
  stop(): void {
    if (this.sub === undefined) {
      return;
    }
    this.sub.cancel();
    this.sub = undefined;
    if (this.level.value === LogLevel.DEBUG) {
      this.engine.setLogLevel(LogLevel.INFO).catch(() => {});
    }
  }

  setLevel(l: LogLevel): void {
    const was = this.level.value;
    if (l === was) {
      return;
    }
    this.level.value = l;
    // 只有日志页开着时才真正抬高内核级别；设置页改级别只记下来。
    if (this.sub !== undefined) {
      if (l === LogLevel.DEBUG) {
        this.engine.setLogLevel(LogLevel.DEBUG).catch(() => {});
      } else if (was === LogLevel.DEBUG) {
        this.engine.setLogLevel(LogLevel.INFO).catch(() => {});
      }
    }
    this.publish();
  }

  togglePause(): void {
    this.paused.value = !this.paused.value;
  }

  clear(): void {
    this.buffer = [];
    this.publish();
  }

  /**
   * 纯文本导出（核心已脱敏），每行 "HH:mm:ss.SSS W message"（同 Android LogsModel.format）。
   * diagnostics 不为空时放在日志前面，中间空一行（§16.c 共享诊断数据）。
   */
  exportText(diagnostics?: string, tzOffsetMin?: number): string {
    const log = this.visible().map((l: LogLine) => LogsModel.format(l, tzOffsetMin)).join('\n');
    return diagnostics === undefined ? log : diagnostics + '\n\n' + log;
  }

  /**
   * §16.c 诊断摘要：App 版本、系统版本、设置（去掉 trustedWifi）、最近 20 个错误码及时间。
   * 与 Android diagnosticsSummary 同格式；鸿蒙目前没有错误环形缓冲，errors 由调用方给（M2 接内核后补）。
   */
  static diagnosticsSummary(appVersion: string, os: string, settings: Settings, errors: DiagError[],
    tzOffsetMin?: number): string {
    const all = JSON.parse(SettingsCodec.encode(settings)) as Record<string, Object>;
    const o: Record<string, Object> = {};
    for (const k of Object.keys(all)) {
      if (k !== 'trustedWifi') {
        o[k] = all[k];
      }
    }
    let out = '# Zephyr diagnostics\n' + 'app: ' + appVersion + '\n' + 'os: ' + os + '\n' + 'settings: ' + JSON.stringify(o) +
      '\n' + 'errors:';
    if (errors.length === 0) {
      out += ' none';
    }
    for (const e of errors.slice(Math.max(0, errors.length - RECENT_ERRORS_MAX))) {
      const d = LogsModel.local(e.at, tzOffsetMin);
      out += '\n  ' + d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1, 2) + '-' + pad(d.getUTCDate(), 2) + ' ' +
        LogsModel.time(e.at, tzOffsetMin) + ' ' + e.code.toLowerCase();
    }
    return out;
  }

  static format(l: LogLine, tzOffsetMin?: number): string {
    return LogsModel.time(l.at, tzOffsetMin) + ' ' + LogsModel.badge(l.level) + ' ' + l.message;
  }

  /** HH:mm:ss.SSS，按本地时区（测试可传固定偏移，分钟，东八区 = 480）。 */
  static time(ms: number, tzOffsetMin?: number): string {
    const d = LogsModel.local(ms, tzOffsetMin);
    return pad(d.getUTCHours(), 2) + ':' + pad(d.getUTCMinutes(), 2) + ':' + pad(d.getUTCSeconds(), 2) + '.' +
      pad(d.getUTCMilliseconds(), 3);
  }

  static badge(l: LogLevel): string {
    switch (l) {
      case LogLevel.DEBUG:
        return 'D';
      case LogLevel.WARNING:
        return 'W';
      case LogLevel.ERROR:
        return 'E';
      default:
        return 'I';
    }
  }

  private static local(ms: number, tzOffsetMin?: number): Date {
    const off = tzOffsetMin !== undefined ? tzOffsetMin : -new Date(ms).getTimezoneOffset();
    return new Date(ms + off * 60000);
  }

  append(line: LogLine): void {
    if (this.paused.value) {
      return;
    }
    this.buffer.push(line);
    if (this.buffer.length > LOG_CAPACITY) {
      this.buffer.splice(0, this.buffer.length - LOG_CAPACITY);
    }
    this.publish();
  }

  visible(): LogLine[] {
    const min = logLevelRank(this.level.value);
    return this.buffer.filter((l: LogLine) => logLevelRank(l.level) >= min);
  }

  private publish(): void {
    this.lines.value = this.visible();
  }
}
