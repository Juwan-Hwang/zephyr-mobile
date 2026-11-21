import { describe, expect, it } from '@ohos/hypium';
import { ROUTE_TODAY, AppNav } from '../../../main/ets/app/AppNav';
import { TODAY_STRANDS, TodayArt, TodayStyle } from '../../../main/ets/app/TodayArt';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { UsageSummary } from '../../../main/ets/engine/Model';

/* 今日卡（M1-9 / U13）：三配色、透明度、流场确定且振幅随流量、统计。 */

export default function todayTest(): void {
  describe('TodayArt', () => {
    it('palettes and alpha', 0, () => {
      expect(TodayArt.palette(TodayStyle.NIGHT).bg).assertEqual('#02040A');
      expect(TodayArt.palette(TodayStyle.DAWN).line).assertEqual('#E07A4F');
      expect(TodayArt.withAlpha('#FFFFFF', 0.6)).assertEqual('#99FFFFFF');
      expect(TodayArt.alpha(TODAY_STRANDS) < 0.06).assertTrue();
    });

    it('flow field is deterministic and follows traffic', 0, () => {
      const flat: number[] = [];
      const busy: number[] = [];
      for (let i = 0; i < 24; i++) {
        flat.push(0);
        busy.push(100);
      }
      expect(JSON.stringify(TodayArt.strand(busy, 300, 440, 70, 0))).assertEqual(
        JSON.stringify(TodayArt.strand(busy, 300, 440, 70, 0)));
      const base = 440 * (0.12 + 0.55 * 70 / TODAY_STRANDS) + 70 / TODAY_STRANDS * 150 * 0.12;
      const quiet = Math.abs(TodayArt.y(flat, 1, 300, 440, 70, 150, 0) - base);
      const loud = Math.abs(TodayArt.y(busy, 100, 300, 440, 70, 150, 0) - base);
      expect(loud > quiet).assertTrue();
    });

    it('stats from usage', 0, async () => {
      const u: UsageSummary = await new MockEngine({ latencyScale: 0 }).usageToday();
      const s = TodayArt.stats(u);
      expect(s.hours).assertEqual(Math.floor(u.onlineMillisToday / 3600000));
      expect(TodayArt.stats(undefined).fastest).assertEqual('—');
      expect(AppNav.isRoute(ROUTE_TODAY)).assertTrue();
    });
  });
}
