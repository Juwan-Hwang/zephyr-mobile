import { describe, expect, it } from '@ohos/hypium';
import { ToastCenter, ToastState, ToastTimers, UNDO_WINDOW_MS, UNDO_WINDOW_SCREEN_READER_MS } from '../../../main/ets/app/ToastCenter';

/* §16.e⑥ 撤销窗口：5 s / 读屏 15 s；撤销不提交；到期 / 顶替提交；读屏焦点期间暂停。 */

class FakeTimers implements ToastTimers {
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

export default function toastTest(): void {
  describe('ToastCenter', () => {
    it('window 5 s, 15 s with screen reader', 0, () => {
      expect(new ToastCenter(() => false, new FakeTimers()).windowMs()).assertEqual(UNDO_WINDOW_MS);
      expect(new ToastCenter(() => true, new FakeTimers()).windowMs()).assertEqual(UNDO_WINDOW_SCREEN_READER_MS);
      expect(UNDO_WINDOW_MS).assertEqual(5000);
      expect(UNDO_WINDOW_SCREEN_READER_MS).assertEqual(15000);
    });

    it('expires and commits', 0, () => {
      const t = new FakeTimers();
      const c = new ToastCenter(() => false, t);
      const log: string[] = [];
      c.show('deleted', { onUndo: () => log.push('undo'), onCommit: () => log.push('commit') });
      const shown: ToastState | undefined = c.current.value;
      expect(shown !== undefined && shown.undoable).assertTrue();
      t.advance(4999);
      expect(log.length).assertEqual(0);
      t.advance(1);
      expect(JSON.stringify(log)).assertEqual('["commit"]');
      expect(c.current.value === undefined).assertTrue();
    });

    it('undo skips commit', 0, () => {
      const t = new FakeTimers();
      const c = new ToastCenter(() => false, t);
      const log: string[] = [];
      const id = c.show('deleted', { onUndo: () => log.push('undo'), onCommit: () => log.push('commit') });
      c.undo(id);
      t.advance(10000);
      expect(JSON.stringify(log)).assertEqual('["undo"]');
    });

    it('a new toast commits the previous one', 0, () => {
      const t = new FakeTimers();
      const c = new ToastCenter(() => false, t);
      const log: string[] = [];
      const first = c.show('a', { onUndo: () => log.push('undo a'), onCommit: () => log.push('commit a') });
      c.show('b');
      c.undo(first);
      expect(JSON.stringify(log)).assertEqual('["commit a"]');
      const cur: ToastState | undefined = c.current.value;
      expect(cur !== undefined && cur.message === 'b' && !cur.undoable).assertTrue();
    });

    it('accessibility focus holds the toast', 0, () => {
      const t = new FakeTimers();
      const c = new ToastCenter(() => true, t);
      const log: string[] = [];
      const id = c.show('x', { onUndo: () => log.push('undo'), onCommit: () => log.push('commit') });
      t.advance(10000);
      c.setFocused(id, true);
      t.advance(60000);
      expect(log.length).assertEqual(0);
      c.setFocused(id, false);
      t.advance(14999);
      expect(log.length).assertEqual(0);
      t.advance(1);
      expect(JSON.stringify(log)).assertEqual('["commit"]');
    });
  });
}
