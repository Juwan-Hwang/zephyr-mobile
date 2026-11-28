import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { AppServices } from '../../../main/ets/app/AppServices';
import { ToastCenter, ToastEvent, UNDO_WINDOW_MS } from '../../../main/ets/app/ToastCenter';
import { UndoableDelete } from '../../../main/ets/app/UndoableDelete';
import { TOAST_MESSAGE_ID, TOAST_UNDO_ID } from '../../../main/ets/components/ZToastHost';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { Subscription } from '../../../main/ets/engine/Model';
import { ZephyrEngine } from '../../../main/ets/engine/ZephyrEngine';
import { FakeTimers, sleep } from './FakeTimers';

/*
 * 订阅删除 → 撤销（§16.e⑥）走订阅页同一份流程（UndoableDelete）：
 * - 逻辑：MockEngine + ToastCenter（假计时器）：撤销后引擎从未删除、列表取消隐藏；到期 / 顶替才删除。
 * - 界面（真机 / 云调试）：拉起 EntryAbility，让首页把吐司浮层挂上，用 UiTest 点真正的“撤销”按钮（按 id 找）。
 *   旧实现卡片 HitTestMode.Block 屏蔽了子节点，这条用例会失败（点不到 → 窗口到期 → 删除）。
 */

class Flow {
  hidden: string[] = [];
  errors: number = 0;
  log: string[] = [];

  run(toasts: ToastCenter, engine: ZephyrEngine, s: Subscription): number {
    return UndoableDelete.run(toasts, {
      message: 'deleted ' + s.name,
      hide: () => {
        this.hidden.push(s.id);
      },
      unhide: () => {
        this.hidden = this.hidden.filter((x: string) => x !== s.id);
      },
      commit: () => engine.deleteSubscription(s.id),
      onError: () => {
        this.errors++;
      },
      log: (m: string) => {
        this.log.push(m);
      }
    });
  }
}

function has(engine: ZephyrEngine, id: string): boolean {
  return engine.subscriptions().value.some((s: Subscription) => s.id === id);
}

export default function undoDeleteTest(): void {
  describe('UndoableDeleteFlow', () => {
    it('undo keeps the subscription', 0, async () => {
      const engine = new MockEngine({ latencyScale: 0 });
      const t = new FakeTimers();
      const toasts = new ToastCenter(() => false, t);
      const events: string[] = [];
      toasts.onEvent = (e: ToastEvent, serial: number, d: string) => {
        events.push(e + ':' + d);
      };
      const s = engine.subscriptions().value[0];
      const n = engine.subscriptions().value.length;
      const f = new Flow();
      f.run(toasts, engine, s);
      expect(f.hidden.indexOf(s.id) >= 0).assertTrue();
      expect(has(engine, s.id)).assertTrue();
      expect(toasts.undoCurrent()).assertTrue();
      expect(f.hidden.length).assertEqual(0);
      t.advance(UNDO_WINDOW_MS * 4);
      await sleep(10);
      expect(engine.subscriptions().value.length).assertEqual(n);
      expect(f.log.indexOf('commit ran: deleting') < 0).assertTrue();
      expect(events.join(',')).assertEqual('show:undoable,undo:');
      // 窗口已过再点撤销：记录 undo_missed，不崩。
      expect(toasts.undoCurrent()).assertFalse();
      expect(events[events.length - 1]).assertEqual('undo_missed:no pending toast');
    });

    it('timeout and replacement delete', 0, async () => {
      const engine = new MockEngine({ latencyScale: 0 });
      const t = new FakeTimers();
      const toasts = new ToastCenter(() => false, t);
      const list = engine.subscriptions().value;
      const a = list[0];
      const b = list[1];
      const f = new Flow();
      f.run(toasts, engine, a);
      f.run(toasts, engine, b);
      await sleep(10);
      expect(has(engine, a.id)).assertFalse();
      expect(has(engine, b.id)).assertTrue();
      expect(f.hidden).assertDeepEquals([b.id]);
      t.advance(UNDO_WINDOW_MS);
      await sleep(10);
      expect(has(engine, b.id)).assertFalse();
      expect(f.hidden.length).assertEqual(0);
      expect(f.errors).assertEqual(0);
    });
  });

  describe('ToastOverlayUi', () => {
    it('tapping 撤销 on the real overlay restores the subscription', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      const svc = AppServices.get();
      const engine = svc.engine;
      const s = engine.subscriptions().value[0];
      expect(s !== undefined).assertTrue();
      const f = new Flow();
      f.run(svc.toasts, engine, s);
      const driver = Driver.create();
      const undo = await driver.waitForComponent(ON.id(TOAST_UNDO_ID), 3000);
      expect(undo !== null && undo !== undefined).assertTrue();
      await undo.click();
      await sleep(UNDO_WINDOW_MS + 1500);
      expect(f.log.indexOf('undo ran: unhide, nothing deleted') >= 0).assertTrue();
      expect(has(engine, s.id)).assertTrue();
      expect(f.hidden.length).assertEqual(0);
    });

    it('tapping the message commits at once', 0, async () => {
      const svc = AppServices.get();
      const engine = svc.engine;
      const list = engine.subscriptions().value;
      const s = list[list.length - 1];
      const f = new Flow();
      f.run(svc.toasts, engine, s);
      const driver = Driver.create();
      const msg = await driver.waitForComponent(ON.id(TOAST_MESSAGE_ID), 3000);
      await msg.click();
      await sleep(500);
      expect(f.log.indexOf('commit ran: deleting') >= 0).assertTrue();
      expect(has(engine, s.id)).assertFalse();
    });
  });
}
