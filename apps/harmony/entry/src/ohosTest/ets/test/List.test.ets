import mockFixturesTest from './MockFixtures.test';
import mockEngineTest from './MockEngine.test';
import settingsTest from './Settings.test';
import toastTest from './Toast.test';
import sceneSlotsTest from './SceneSlots.test';
import navTest from './Nav.test';

export default function testsuite(): void {
  mockFixturesTest();
  mockEngineTest();
  settingsTest();
  toastTest();
  sceneSlotsTest();
  navTest();
}
