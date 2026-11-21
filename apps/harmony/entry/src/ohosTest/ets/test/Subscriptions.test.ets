import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, Rect } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { AppServices } from '../../../main/ets/app/AppServices';
import { LibraryDest } from '../../../main/ets/app/AppNav';
import { ReviewKind, SubscriptionsModel, SubscriptionWarning } from '../../../main/ets/app/SubscriptionsModel';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { copySettings, Subscription, SubscriptionDiff } from '../../../main/ets/engine/Model';
import { HOME_LIBRARY_ID } from '../../../main/ets/views/HomeView';
import { libraryTileId } from '../../../main/ets/views/LibrarySheet';
import { SUBS_REVIEW_CONFIRM_ID, SUBS_REVIEW_ID, subsRowId, subsSwipeUpdateId } from '../../../main/ets/views/SubscriptionsView';
import { sleep } from './FakeTimers';

/* 订阅页（M1-11 / U19–U21）：§16.e④ 琥珀、更新前预览求和、分组；界面：左滑“更新” → 差异确认卡 → 更新。 */

const DAY: number = 86400000;

function sub(id: string, expiresAt: number | undefined, used: number | undefined, total: number | undefined): Subscription {
  const s: Subscription = {
    id: id, name: id, nodeCount: 5, autoUpdateHours: 12, expiresAt: expiresAt, usedBytes: used, totalBytes: total
  };
  return s;
}

function diff(a: number, kept: boolean, retested: boolean): SubscriptionDiff {
  const d: SubscriptionDiff = { addedNodes: a, removedNodes: 1, ruleChanges: 2, overridesKept: kept, scenesRetested: retested };
  return d;
}

export default function subscriptionsTest(): void {
  describe('SubscriptionsModel', () => {
    it('amber rule §16.e④', 0, () => {
      const now = new Date(2026, 10, 20, 23, 0).getTime();
      expect(SubscriptionWarning.isWarning(sub('orbit', now + 3 * DAY, 88, 100), now)).assertTrue();
      expect(SubscriptionWarning.isWarning(sub('nebula', now + 26 * DAY, 57, 100), now)).assertFalse();
      expect(SubscriptionWarning.expiresSoon(new Date(2026, 10, 27, 12).getTime(), now)).assertTrue();
      expect(SubscriptionWarning.expiresSoon(new Date(2026, 10, 28, 1).getTime(), now)).assertFalse();
      expect(SubscriptionWarning.mostlyUsed(5, 0)).assertFalse();
    });

    it('preview sums and groups', 0, async () => {
      const s = SubscriptionsModel.sum([diff(1, true, false), diff(10, false, true)]);
      expect(s.addedNodes).assertEqual(11);
      expect(s.overridesKept).assertFalse();
      expect(s.scenesRetested).assertTrue();
      const e = new MockEngine({ latencyScale: 0 });
      const all = await SubscriptionsModel.previewAll(e);
      expect(all !== undefined && all.kind === ReviewKind.ALL && all.count === e.subscriptions().value.length).assertTrue();
      const g = SubscriptionsModel.groups([sub('m', undefined, 1, 100), sub('u', undefined, undefined, undefined)],
        { count: 3, totalNodes: 20 });
      expect(g.metered.length).assertEqual(1);
      expect(g.others).assertEqual(2);
      expect(g.otherNodes).assertEqual(5 + 10);
    });
  });

  describe('SubscriptionsUi', () => {
    it('swipe update → review → update', 0, async () => {
      const svc = AppServices.get();
      const on = copySettings(svc.engine.settings().value);
      on.showChangesBeforeUpdate = true;
      await svc.settings.update(on);
      const target = svc.engine.subscriptions().value.find((x: Subscription) => SubscriptionsModel.isMetered(x));
      expect(target !== undefined).assertTrue();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      const driver = Driver.create();
      await (await driver.waitForComponent(ON.id(HOME_LIBRARY_ID), 3000)).click();
      await sleep(1200);
      await (await driver.waitForComponent(ON.id(libraryTileId(LibraryDest.SUBSCRIPTIONS)), 3000)).click();
      await sleep(1500);
      const row: Component = await driver.waitForComponent(ON.id(subsRowId(target!.id)), 3000);
      const b: Rect = await row.getBounds();
      const y = Math.round((b.top + b.bottom) / 2);
      await driver.swipe(b.right - 20, y, b.left + 40, y, 800);
      await sleep(800);
      await (await driver.waitForComponent(ON.id(subsSwipeUpdateId(target!.id)), 3000)).click();
      await sleep(1500);
      expect((await driver.waitForComponent(ON.id(SUBS_REVIEW_ID), 3000)) !== null).assertTrue();
      const before = target!.updatedAt;
      await (await driver.waitForComponent(ON.id(SUBS_REVIEW_CONFIRM_ID), 3000)).click();
      await sleep(2000);
      const after = svc.engine.subscriptions().value.find((x: Subscription) => x.id === target!.id);
      expect(after !== undefined && after.updatedAt !== before).assertTrue();
      const off = copySettings(svc.engine.settings().value);
      off.showChangesBeforeUpdate = false;
      await svc.settings.update(off);
      await driver.pressBack();
      await sleep(800);
    });
  });
}
