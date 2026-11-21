import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { AppServices } from '../../../main/ets/app/AppServices';
import { LibraryDest } from '../../../main/ets/app/AppNav';
import { CHIP_COUNT, NamePart, RegionChip, NodeListModel, NodeNameParts } from '../../../main/ets/app/NodeListModel';
import { Format } from '../../../main/ets/common/Format';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { NodeQueryResult, RegionSection } from '../../../main/ets/engine/Model';
import { HOME_LIBRARY_ID } from '../../../main/ets/views/HomeView';
import { libraryTileId } from '../../../main/ets/views/LibrarySheet';
import { NODES_DETAIL_TEST_ID, NODES_LIST_ID, NODES_PINNED_ID, NODES_RAIL_ID, nodeRowId } from '../../../main/ets/views/NodesView';
import { sleep } from './FakeTimers';

/* 节点页（M1-10 / U14、U15）：chips、高亮、自动测速规则、置顶分区头、位置；界面：资料库 → 节点 → 详情 → 测速。 */

function sec(region: string, count: number): RegionSection {
  const s: RegionSection = { region: region, name: region, count: count, rowOffset: 0 };
  return s;
}

function joined(parts: NamePart[]): string {
  return parts.map((p: NamePart) => p.kind.charAt(0) + ':' + p.text).join('|');
}

export default function nodesTest(): void {
  describe('NodeListModel M1-10', () => {
    it('chips: top 8 non-empty by count', 0, () => {
      const c = NodeListModel.chipsOf([sec('A', 0), sec('B', 5), sec('C', 9)]);
      expect(c.map((x: RegionChip) => x.region).join()).assertEqual('C,B');
      expect(CHIP_COUNT).assertEqual(8);
      expect(Format.chip(1234, false, '万')).assertEqual('1.2K');
      expect(Format.chip(2204117, true, '万')).assertEqual('220 万');
    });

    it('name highlight like Android', 0, () => {
      expect(joined(NodeNameParts.split('Tokyo IIJ 03 ×1.5', ['tokyo', 'iij']))).assertEqual('h:Tokyo|p: |h:IIJ|p: 03|m: ×1.5');
      expect(joined(NodeNameParts.split('aaa', ['aa', 'a']))).assertEqual('h:aa|p:a');
    });

    it('auto test: wifi-only + metered holds back', 0, async () => {
      expect(NodeListModel.autoTestAllowed(true, true)).assertFalse();
      expect(NodeListModel.autoTestAllowed(false, true)).assertTrue();
      const e = new MockEngine({ latencyScale: 0 });
      const m = new NodeListModel(e);
      m.start();
      await m.query('');
      m.setVisible(0, 15);
      m.item(1);
      await sleep(50);
      const ids = m.autoTestIds();
      expect(ids.length > 0).assertTrue();
      expect(m.autoTest(true)).assertEqual(0);
      expect(m.autoTest(false)).assertEqual(ids.length);
      await sleep(100);
      expect(m.latencyOf(ids[0]) !== undefined).assertTrue();
      expect(m.autoTestIds().length).assertEqual(0);
      const secs = m.sections();
      m.setVisible(secs[1].rowOffset, secs[1].rowOffset + 5);
      expect(m.position()).assertEqual(secs[0].count + 1);
      expect(m.sectionAt(secs[1].rowOffset + 2)?.region).assertEqual(secs[1].region);
      m.dispose();
    });
  });

  describe('NodesUi', () => {
    it('library → nodes → detail → test', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = { bundleName: 'com.juwanh.zephyr', abilityName: 'EntryAbility' };
      await delegator.startAbility(want);
      await sleep(2500);
      const driver = Driver.create();
      const lib: Component = await driver.waitForComponent(ON.id(HOME_LIBRARY_ID), 3000);
      await lib.click();
      await sleep(1200);
      const tile: Component = await driver.waitForComponent(ON.id(libraryTileId(LibraryDest.NODES)), 3000);
      await tile.click();
      await sleep(1500);
      const list: Component = await driver.waitForComponent(ON.id(NODES_LIST_ID), 3000);
      expect(list !== null && list !== undefined).assertTrue();
      expect((await driver.findComponent(ON.id(NODES_RAIL_ID))) !== null).assertTrue();
      // 第一个节点行（首个分区第 0 个）。
      const engine = AppServices.get().engine;
      const r: NodeQueryResult = await engine.queryNodes('');
      const first = (await engine.nodeRows(r.token, 0, 1)).rows[0];
      const later = (await engine.nodeRows(r.token, 30, 1)).rows[0];
      const row: Component = await driver.waitForComponent(ON.id(nodeRowId(first.id)), 3000);
      // 滑一屏后出现置顶分区头。
      await list.scrollSearch(ON.id(nodeRowId(later.id)));
      await sleep(800);
      expect((await driver.findComponent(ON.id(NODES_PINNED_ID))) !== null).assertTrue();
      await list.scrollToTop();
      await sleep(800);
      await row.click();
      await sleep(1500);
      const test: Component = await driver.waitForComponent(ON.id(NODES_DETAIL_TEST_ID), 3000);
      await test.click();
      await sleep(1500);
      await driver.pressBack();
      await sleep(800);
      await driver.pressBack();
      await sleep(800);
    });
  });
}
