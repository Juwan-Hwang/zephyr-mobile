import mockFixturesTest from './MockFixtures.test';
import mockEngineTest from './MockEngine.test';
import settingsTest from './Settings.test';
import toastTest from './Toast.test';
import sceneSlotsTest from './SceneSlots.test';
import navTest from './Nav.test';
import commandParseTest from './CommandParse.test';
import sceneSheetTest from './SceneSheet.test';
import traceTest from './Trace.test';
import todayTest from './Today.test';
import vpnTest from './Vpn.test';
import undoDeleteTest from './UndoDelete.test';
import commandApplyTest from './CommandApply.test';
import sceneOpenTest from './SceneOpen.test';

export default function testsuite(): void {
  mockFixturesTest();
  mockEngineTest();
  settingsTest();
  toastTest();
  sceneSlotsTest();
  navTest();
  commandParseTest();
  sceneSheetTest();
  traceTest();
  todayTest();
  vpnTest();
  undoDeleteTest();
  commandApplyTest();
  sceneOpenTest();
}
