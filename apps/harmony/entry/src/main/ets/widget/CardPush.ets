/*
 * 把服务卡片快照推给已添加的卡片（formProvider.updateForm）。UI 进程（状态变化时）与 VPN 扩展进程（连接期间每 60 s，
 * 契约 §17.c / #297：UI 进程退到后台会被冻结，周期刷新必须由常驻的扩展进程发起）共用。
 * 扩展进程不加载引擎：只读 UI 写好的 card-snapshot.json，经 forDisplay 处理零点重置后再推。
 */
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshot, CardSnapshots } from './CardSnapshot';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x5A50;
const TAG: string = 'CardPush';

export class CardPush {
  /** 推给每张卡片；快照已由调用方存好。 */
  static push(filesDir: string, s: CardSnapshot): void {
    CardStore.ids(filesDir).forEach((entry: string) => {
      const id = CardSnapshots.idOf(entry);
      const data = formBindingData.createFormBindingData(CardSnapshots.binding(s, CardSnapshots.isWide(entry)));
      formProvider.updateForm(id, data).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', id, String(e));
      });
    });
  }

  /** 读文件里的最新快照再推（扩展进程的 60 s 循环）。 */
  static republish(filesDir: string): void {
    if (CardStore.ids(filesDir).length === 0) {
      return;
    }
    CardPush.push(filesDir, CardSnapshots.forDisplay(CardStore.snapshot(filesDir), Date.now()));
  }
}
