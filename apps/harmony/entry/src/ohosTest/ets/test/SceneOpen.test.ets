import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { sceneRowId } from '../../../main/ets/views/SceneRow';
import { sleep } from './FakeTimers';

/*
 * 真机（Mate 90）：点“视频”场景行两次没打开 sheet（AI 行可以）。云调试记录里第一下落在仍开着的 AI sheet 的遮罩上
 * （只会收起 AI sheet），第二下 x=175 在设备画面外（画面从 x=195 开始）。这里在真机 / 云调试上按真实流程验证：
 * 每一行点按都打开自己的 sheet；AI sheet 开着时点视频行：第一下收起 AI sheet，第二下打开视频 sheet。
 * 首页另外防住了 showScene 残留为 true 时“点了没反应”（HomeView.openScene 先复位再打开）。
 */

function str(name: string, fallback: string): string {
  try {
    return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().resourceManager.getStringByNameSync(name);
  } catch (e) {
    return fallback;
  }
}

async function sheetOpen(driver: Driver): Promise<boolean> {
  const c = await driver.findComponent(ON.text(str('scene_test_frequency', '检测频率')));
  return c !== null && c !== undefined;
}

async function tapRow(driver: Driver, id: string): Promise<void> {
  const row: Component = await driver.waitForComponent(ON.id(sceneRowId(id)), 3000);
  expect(row !== null && row !== undefined).assertTrue();
  await row.click();
  await sleep(1200);
}

export default function sceneOpenTest(): void {
  describe('SceneRowOpenUi', () => {
    it('every scene row opens its sheet, video included', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      const driver = Driver.create();
      for (const id of ['ai', 'video', 'other']) {
        await tapRow(driver, id);
        expect(await sheetOpen(driver)).assertTrue();
        await driver.pressBack();
        await sleep(1000);
        expect(await sheetOpen(driver)).assertFalse();
      }
    });

    it('video row while the AI sheet is open: second tap opens video', 0, async () => {
      const driver = Driver.create();
      const videoRow: Component = await driver.waitForComponent(ON.id(sceneRowId('video')), 3000);
      const p = await videoRow.getBoundsCenter();
      await tapRow(driver, 'ai');
      expect(await sheetOpen(driver)).assertTrue();
      // 第一下：遮罩收起 AI sheet；第二下：打开视频。
      await driver.click(p.x, p.y);
      await sleep(1200);
      await driver.click(p.x, p.y);
      await sleep(1200);
      expect(await sheetOpen(driver)).assertTrue();
      await driver.pressBack();
      await sleep(800);
    });
  });
}
