import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { AppServices } from '../../../main/ets/app/AppServices';
import { CloseOutcome, RECENT_HOSTS_MAX, RecentHostsModel } from '../../../main/ets/app/RecentHostsModel';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { ConnectionInfo } from '../../../main/ets/engine/Model';
import { recentHostRowId } from '../../../main/ets/views/ActivitySheet';
import { HOME_TRAFFIC_ID } from '../../../main/ets/views/HomeView';
import { sleep } from './FakeTimers';

/* 最近连接（M1-8 / U11，§16.e⑧）：聚合列表、副标题、长按关闭的吐司结果；界面：首页速率区 → 列表 → 轨迹 → 返回。 */

function conn(host: string, scene: string | undefined, app: string | undefined): ConnectionInfo {
  const c: ConnectionInfo = {
    id: host, host: host, scene: scene, app: app, node: 'HK 01', upBytes: 1, downBytes: 2, startedAt: 0
  };
  return c;
}

function str(name: string, fallback: string): string {
  try {
    return abilityDelegatorRegistry.getAbilityDelegator().getAppContext().resourceManager.getStringByNameSync(name);
  } catch (e) {
    return fallback;
  }
}

export default function recentHostsTest(): void {
  describe('RecentHostsModel', () => {
    it('close messages like Android', 0, () => {
      expect(RecentHostsModel.closeResult(0, 0).outcome).assertEqual(CloseOutcome.NONE);
      expect(RecentHostsModel.closeResult(3, 3).count).assertEqual(3);
      expect(RecentHostsModel.closeResult(0, 2).outcome).assertEqual(CloseOutcome.FAILED);
      const p = RecentHostsModel.closeResult(1, 3);
      expect(p.outcome).assertEqual(CloseOutcome.PARTIAL);
      expect(p.count).assertEqual(2);
    });

    it('subtitle and note', 0, () => {
      expect(RecentHostsModel.subtitleParts(conn('qq.com', undefined, undefined), '').length).assertEqual(0);
      expect(RecentHostsModel.subtitleParts(conn('a.com', 'AI', 'Chrome'), 'AI').join(' · ')).assertEqual('Chrome · AI · HK 01');
      expect(RecentHostsModel.showsNoAppNote([conn('a', 'AI', undefined)])).assertTrue();
      expect(RecentHostsModel.showsNoAppNote([conn('a', 'AI', 'X'), conn('b', 'AI', undefined)])).assertFalse();
      expect(RecentHostsModel.showsNoAppNote([])).assertFalse();
      expect(RECENT_HOSTS_MAX).assertEqual(50);
    });

    it('close host against the mock engine', 0, async () => {
      const e = new MockEngine({ latencyScale: 0 });
      expect((await RecentHostsModel.closeHost(e, 'claude.ai', 200)).outcome).assertEqual(CloseOutcome.NONE);
      await e.connect();
      const r = await RecentHostsModel.closeHost(e, 'claude.ai', 200);
      expect(r.outcome).assertEqual(CloseOutcome.CLOSED);
      expect(r.count).assertEqual(1);
      // 每次取完第一帧都取消订阅（不留 1 Hz 计时器）。
      expect(e.activeConnections().subscriberCount).assertEqual(0);
    });
  });

  describe('RecentHostsUi', () => {
    it('traffic → list → trace → back', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      await AppServices.get().engine.connect();
      await sleep(800);
      const driver = Driver.create();
      const traffic: Component = await driver.waitForComponent(ON.id(HOME_TRAFFIC_ID), 3000);
      await traffic.click();
      await sleep(1500);
      const row: Component = await driver.waitForComponent(ON.id(recentHostRowId('claude.ai')), 3000);
      expect(row !== null && row !== undefined).assertTrue();
      await row.click();
      await sleep(1500);
      const back: Component = await driver.waitForComponent(ON.text(str('activity_back', '‹ 最近连接')), 3000);
      expect(back !== null && back !== undefined).assertTrue();
      await back.click();
      await sleep(1000);
      const again = await driver.findComponent(ON.id(recentHostRowId('claude.ai')));
      expect(again !== null && again !== undefined).assertTrue();
      await driver.pressBack();
      await sleep(800);
    });
  });
}
