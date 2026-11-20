import mockFixturesTest from './MockFixtures.test';
import mockEngineTest from './MockEngine.test';

export default function testsuite(): void {
  mockFixturesTest();
  mockEngineTest();
}
