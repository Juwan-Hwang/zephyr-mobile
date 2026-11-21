import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { AppServices } from '../../../main/ets/app/AppServices';
import { CommandApplier, GHOST_TAP_MS } from '../../../main/ets/app/CommandApplier';
import { CommandPlan, CommandPlanner } from '../../../main/ets/app/CommandPlanner';
import { ToastCenter, ToastState } from '../../../main/ets/app/ToastCenter';
import { TOAST_MESSAGE_ID } from '../../../main/ets/components/ZToastHost';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { Scene, SceneKind } from '../../../main/ets/engine/Model';
import { ZephyrEngine } from '../../../main/ets/engine/ZephyrEngine';
import { FakeTimers, sleep } from './FakeTimers';

/*
 * 指令“应用”（真机：点“应用”后面板不关、再点落到首页 AI 行打开了 AI 场景 sheet）：
 * - 逻辑：先关面板再执行（同 Android），吐司带撤销，撤销回到原节点；面板刚关时首页忽略场景行点按。
 * - 界面：拉起 EntryAbility → 点指令栏 → 输入“视频走日本” → 点“应用”并在同一位置立刻再点一次（模拟云调试上的二次点按）
 *   → 首页出吐司、视频场景已换到日本、没有打开任何场景 sheet。
 */

function video(e: ZephyrEngine): Scene {
  return e.scenes().value.find((s: Scene) => s.kind === SceneKind.VIDEO) as Scene;
}

function str(name: string, fallback: string): string {
  try {
    return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().resourceManager.getStringByNameSync(name);
  } catch (e) {
    return fallback;
  }
}

export default function commandApplyTest(): void {
  describe('CommandApplier', () => {
    it('closes first, applies, undo restores', 0, async () => {
      const engine = new MockEngine({ latencyScale: 0 });
      const planner = new CommandPlanner(engine);
      const toasts = new ToastCenter(() => false, new FakeTimers());
      const before = video(engine).selected.id;
      const p = await planner.planText('视频走日本') as CommandPlan;
      expect(p !== undefined && p.applicable).assertTrue();
      const order: string[] = [];
      toasts.current.subscribe((t: ToastState | undefined) => {
        if (t !== undefined) {
          order.push('toast:' + String(t.undoable));
        }
      });
      const run = CommandApplier.run(planner, p, toasts, { success: 'ok', failed: 'fail' }, () => {
        order.push('close:' + String(video(engine).selected.region));
      });
      // close 在 apply 之前、同步发生。
      expect(order.length).assertEqual(1);
      expect(await run).assertTrue();
      expect(order[1]).assertEqual('toast:true');
      expect(video(engine).selected.region).assertEqual('JP');
      expect(toasts.undoCurrent()).assertTrue();
      await sleep(20);
      expect(video(engine).selected.id).assertEqual(before);
    });

    it('already on that region still applies and toasts', 0, async () => {
      const engine = new MockEngine({ latencyScale: 0 });
      const planner = new CommandPlanner(engine);
      const toasts = new ToastCenter(() => false, new FakeTimers());
      const p = await planner.planText('视频 香港') as CommandPlan;
      let closed = 0;
      expect(await CommandApplier.run(planner, p, toasts, { success: 'ok', failed: 'fail' }, () => {
        closed++;
      })).assertTrue();
      expect(closed).assertEqual(1);
      expect(toasts.current.value !== undefined && toasts.current.value.message === 'ok').assertTrue();
    });

    it('ghost tap window', 0, () => {
      expect(CommandApplier.suppressesTap(0, 1000)).assertFalse();
      expect(CommandApplier.suppressesTap(1000, 1000 + GHOST_TAP_MS - 1)).assertTrue();
      expect(CommandApplier.suppressesTap(1000, 1000 + GHOST_TAP_MS)).assertFalse();
    });
  });

  describe('CommandApplyUi', () => {
    it('apply closes the sheet and a second tap opens nothing', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      const engine = AppServices.get().engine;
      const driver = Driver.create();
      const bar: Component = await driver.waitForComponent(ON.text(str('command_placeholder', '搜索或输入指令')), 3000);
      await bar.click();
      await sleep(1000);
      const input: Component = await driver.waitForComponent(ON.type('TextInput'), 3000);
      await input.inputText('视频走日本');
      await sleep(1000);
      const apply: Component = await driver.waitForComponent(ON.text(str('term_apply', '应用')), 3000);
      const r = await apply.getBounds();
      const x = Math.round((r.left + r.right) / 2);
      const y = Math.round((r.top + r.bottom) / 2);
      await apply.click();
      await sleep(250);
      await driver.click(x, y);
      await sleep(1500);
      expect(video(engine).selected.region).assertEqual('JP');
      const toast = await driver.findComponent(ON.id(TOAST_MESSAGE_ID));
      expect(toast !== null && toast !== undefined).assertTrue();
      const sheet = await driver.findComponent(ON.text(str('scene_test_frequency', '检测频率')));
      expect(sheet === null || sheet === undefined).assertTrue();
    });
  });
}
