/*
 * 设置 › 诊断 › 日志（对照 Android LogsModel）：订阅 engine.logs()，按所选级别过滤，保留最新 CAPACITY 行。
 * - §16.h：选 debug 时 engine.setLogLevel('debug')，离开日志页（stop）或改回其它级别时回 info。
 *   warning / error 只过滤显示，info 历史保留。
 * - 暂停只停止追加；清空只清本地缓冲。
 * 进程内单例（AppServices.logs）：设置页的“日志级别”与日志页共用同一级别。
 */
import { LogLevel, logLevelRank, LogLine } from '../engine/Model';
import { StateStream, Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export const LOG_CAPACITY: number = 500;

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

  /** 纯文本导出（核心已脱敏）。 */
  exportText(): string {
    return this.visible().map((l: LogLine) => new Date(l.at).toISOString() + ' ' + String(l.level).toUpperCase() + ' ' + l.message).join('\n');
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
