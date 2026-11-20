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
    this.finish(true);
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
    if (p.onUndo !== undefined) {
      p.onUndo();
    }
  }

  /** 关闭（提交）指定吐司。 */
  dismiss(serial: number): void {
    if (this.pending !== undefined && this.pending.state.serial === serial) {
      this.finish(true);
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
        this.finish(true);
      }
    }, p.state.durationMs);
  }

  private finish(commit: boolean): void {
    const p = this.pending;
    if (p === undefined) {
      return;
    }
    this.timers.clear(p.timer);
    this.pending = undefined;
    this.current.value = undefined;
    if (commit && p.onCommit !== undefined) {
      p.onCommit();
    }
  }
}
