import mockFixturesTest from './MockFixtures.test';
import mockEngineTest from './MockEngine.test';
import settingsTest from './Settings.test';
import toastTest from './Toast.test';

export default function testsuite(): void {
  mockFixturesTest();
  mockEngineTest();
  settingsTest();
  toastTest();
}
