/*
 * 吐司与撤销（契约 §16.e⑥，U23；对照 iOS UndoToast / Android ZToast）。
 * - 同一时间只有一条；新吐司到来时上一条立即“提交”（执行其 onCommit，不再可撤销）。
 * - 撤销窗口：默认 5000 ms（tokens motion.undo-window）；读屏开启时 15000 ms（与 iOS 同；鸿蒙无 Android 那样的推荐超时 API）。
 * - 吐司获得无障碍焦点期间不消失（setFocused 暂停计时，失焦后重新给满一个窗口）。
 * - 撤销：执行 onUndo，不执行 onCommit。到期 / 被顶替 / 手动关闭：执行 onCommit。
 * 纯逻辑，计时器与读屏判断可注入（单测）。ZToastHost 负责显示与朗读。
 */
import { StateStream } from '../engine/Stream';

export const UNDO_WINDOW_MS: number = 5000;
export const UNDO_WINDOW_SCREEN_READER_MS: number = 15000;

export interface ToastTimers {
  set(cb: () => void, ms: number): number;
  clear(id: number): void;
}

export interface ToastState {
  serial: number;
  message: string;
  /** 有撤销按钮。 */
  undoable: boolean;
  durationMs: number;
}

/** 吐司生命周期事件（真机排查用：AppServices 接到 hilog）。 */
export enum ToastEvent {
  SHOW = 'show',
  UNDO = 'undo',
  /** 提交原因见 detail：timeout / replaced / dismiss。 */
  COMMIT = 'commit',
  /** 宿主点了撤销，但已没有可撤销的吐司（窗口已过 / 已提交）。 */
  UNDO_MISSED = 'undo_missed'
}

export type ToastListener = (event: ToastEvent, serial: number, detail: string) => void;

export interface ToastOptions {
  onUndo?: () => void;
  onCommit?: () => void;
}

class Pending {
  state: ToastState;
  onUndo: (() => void) | undefined;
  onCommit: (() => void) | undefined;
  timer: number = -1;

  constructor(state: ToastState, opts: ToastOptions | undefined) {
    this.state = state;
    this.onUndo = opts !== undefined ? opts.onUndo : undefined;
    this.onCommit = opts !== undefined ? opts.onCommit : undefined;
  }
}

class SystemTimers implements ToastTimers {
  set(cb: () => void, ms: number): number {
    return setTimeout(cb, ms);
  }

  clear(id: number): void {
    if (id >= 0) {
      clearTimeout(id);
    }
  }
}

export class ToastCenter {
  readonly current: StateStream<ToastState | undefined> = new StateStream<ToastState | undefined>(undefined);
  private timers: ToastTimers;
  private screenReader: () => boolean;
  private pending: Pending | undefined = undefined;
  private serial: number = 0;
  /** 生命周期事件（日志）；不影响行为。 */
  onEvent: ToastListener | undefined = undefined;

  constructor(screenReader: () => boolean, timers?: ToastTimers) {
    this.screenReader = screenReader;
    this.timers = timers ?? new SystemTimers();
  }

  windowMs(): number {
    let on = false;
    try {
      on = this.screenReader();
    } catch (e) {
      on = false;
    }
    return on ? UNDO_WINDOW_SCREEN_READER_MS : UNDO_WINDOW_MS;
  }

  /** 显示一条吐司；返回 serial。带 onUndo 才有“撤销”按钮。 */
  show(message: string, opts?: ToastOptions): number {
    this.finish(true, 'replaced');
    this.serial++;
    const state: ToastState = {
      serial: this.serial,
      message: message,
      undoable: opts !== undefined && opts.onUndo !== undefined,
      durationMs: this.windowMs()
    };
    const p = new Pending(state, opts);
    this.pending = p;
    this.arm(p);
    this.current.value = state;
    this.emitEvent(ToastEvent.SHOW, state.serial, state.undoable ? 'undoable' : '');
    return state.serial;
  }

  undo(serial: number): void {
    const p = this.pending;
    if (p === undefined || p.state.serial !== serial) {
      return;
    }
    this.timers.clear(p.timer);
    this.pending = undefined;
    this.current.value = undefined;
    this.emitEvent(ToastEvent.UNDO, serial, p.onUndo !== undefined ? '' : 'no handler');
    if (p.onUndo !== undefined) {
      p.onUndo();
    }
  }

  /**
   * 撤销当前吐司（宿主“撤销”按钮用）：不依赖界面里缓存的 serial（浮层 ComponentContent 里的状态可能滞后），
   * 只要还有可撤销的吐司就执行其 onUndo 并取消提交计时。返回是否执行了撤销。
   */
  undoCurrent(): boolean {
    const p = this.pending;
    if (p === undefined || p.onUndo === undefined) {
      this.emitEvent(ToastEvent.UNDO_MISSED, p !== undefined ? p.state.serial : this.serial,
        p === undefined ? 'no pending toast' : 'not undoable');
      return false;
    }
    this.undo(p.state.serial);
    return true;
  }

  /** 是否有尚未结束的吐司（单测 / 宿主判断用）。 */
  hasPending(): boolean {
    return this.pending !== undefined;
  }

  /** 关闭（提交）指定吐司。 */
  dismiss(serial: number): void {
    if (this.pending !== undefined && this.pending.state.serial === serial) {
      this.finish(true, 'dismiss');
    }
  }

  /** 读屏焦点在吐司上时暂停计时；离开后重新计一个完整窗口。 */
  setFocused(serial: number, focused: boolean): void {
    const p = this.pending;
    if (p === undefined || p.state.serial !== serial) {
      return;
    }
    this.timers.clear(p.timer);
    p.timer = -1;
    if (!focused) {
      this.arm(p);
    }
  }

  private arm(p: Pending): void {
    p.timer = this.timers.set(() => {
      if (this.pending === p) {
        this.finish(true, 'timeout');
      }
    }, p.state.durationMs);
  }

  private emitEvent(event: ToastEvent, serial: number, detail: string): void {
    const l = this.onEvent;
    if (l !== undefined) {
      try {
        l(event, serial, detail);
      } catch (e) {
        // 日志失败不影响吐司。
      }
    }
  }

  private finish(commit: boolean, reason: string): void {
    const p = this.pending;
    if (p === undefined) {
      return;
    }
    this.timers.clear(p.timer);
    this.pending = undefined;
    this.current.value = undefined;
    if (commit) {
      this.emitEvent(ToastEvent.COMMIT, p.state.serial, reason);
    }
    if (commit && p.onCommit !== undefined) {
      p.onCommit();
    }
  }
}
