import { ToastTimers } from '../../../main/ets/app/ToastCenter';

/** 可手动推进的计时器（吐司撤销窗口测试用）。 */
export class FakeTimers implements ToastTimers {
  now: number = 0;
  private seq: number = 0;
  private due: Map<number, number> = new Map<number, number>();
  private cbs: Map<number, () => void> = new Map<number, () => void>();

  set(cb: () => void, ms: number): number {
    this.seq++;
    this.due.set(this.seq, this.now + ms);
    this.cbs.set(this.seq, cb);
    return this.seq;
  }

  clear(id: number): void {
    this.due.delete(id);
    this.cbs.delete(id);
  }

  advance(ms: number): void {
    this.now += ms;
    const ready: number[] = [];
    this.due.forEach((at: number, id: number) => {
      if (at <= this.now) {
        ready.push(id);
      }
    });
    for (const id of ready) {
      const cb = this.cbs.get(id);
      this.clear(id);
      if (cb !== undefined) {
        cb();
      }
    }
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
