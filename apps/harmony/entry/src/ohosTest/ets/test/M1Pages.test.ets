import { describe, expect, it } from '@ohos/hypium';
import { LatencyTicks, TickSummary } from '../../../main/ets/app/LatencyTicks';
import { LicenseDoc, LicenseRow, Licenses } from '../../../main/ets/app/Licenses';
import { LogsModel } from '../../../main/ets/app/LogsModel';
import { Onboarding } from '../../../main/ets/app/Onboarding';
import { LogLevel, LogLine, NodeSummary, SceneSource } from '../../../main/ets/engine/Model';

/* M1-15 / M1-16 / M1-17 / J-6 纯逻辑：日志行格式、引导显示条件、许可分块、延迟刻度条。 */

function node(id: number, ms: number | undefined): NodeSummary {
  const n: NodeSummary = { id: id, name: 'n' + id, region: 'JP', protocol: '', latencyMs: ms };
  return n;
}

export default function m1PagesTest(): void {
  describe('M1 pages logic', () => {
    it('logs line format HH:mm:ss.SSS + badge', 0, () => {
      const l: LogLine = { at: Date.UTC(2026, 10, 22, 1, 2, 3, 45), level: LogLevel.WARNING, message: 'x' };
      const s = LogsModel.format(l, 0);
      expect(s.startsWith('01:02:03.045 ')).assertTrue();
      expect(s.endsWith('x')).assertTrue();
    });

    it('onboarding shows only on real engine before onboarded', 0, () => {
      expect(Onboarding.shouldShow('mock', false)).assertFalse();
      expect(Onboarding.shouldShow('core', false)).assertTrue();
      expect(Onboarding.shouldShow('core', true)).assertFalse();
      expect(Onboarding.sourceFor(true)).assertEqual(SceneSource.SUBSCRIPTION_GROUP);
      expect(Onboarding.sourceFor(false)).assertEqual(SceneSource.AUTO);
    });

    it('licences split into blocks with headers', 0, () => {
      expect(Licenses.sourceTag('0.3.0')).assertEqual('mobile-v0.3.0');
      expect(Licenses.blocks('a\r\nb\n\n\n  \nc  \n').join('|')).assertEqual('a\nb|c');
      const m = new Map<LicenseDoc, string>();
      m.set(LicenseDoc.NOTICES, 'x\n\ny');
      const rows: LicenseRow[] = Licenses.rows(m);
      expect(rows.length).assertEqual(3);
      expect(rows[0].header).assertTrue();
      expect(Licenses.rows(new Map<LicenseDoc, string>()).length).assertEqual(0);
    });

    it('latency ticks: timeouts, slow, selected last', 0, () => {
      const s: TickSummary = LatencyTicks.summarize([node(1, 38), node(2, 210), node(3, -1), node(4, undefined)], 1);
      expect(s.ticks.length).assertEqual(2);
      expect(s.timeouts).assertEqual(1);
      expect(s.ticks[s.ticks.length - 1].selected).assertTrue();
      expect(LatencyTicks.x(9999, 301)).assertEqual(300.5);
    });
  });
}
