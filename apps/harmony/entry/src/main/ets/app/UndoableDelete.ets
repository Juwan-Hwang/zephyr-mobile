/*
 * 删除 + 撤销的完整流程（契约 §16.e⑥，U23；对照 Android SubscriptionsScreen 删除 / iOS UndoToast）：
 * 确认后先从列表隐藏（hide），出可撤销吐司；撤销 → unhide，引擎从不删除；窗口到期 / 被下一条吐司顶替 / 点文案关闭 →
 * 才调 commit（engine.deleteSubscription），完成或失败都 unhide（列表此后以引擎为准），失败再报 onError。
 * 订阅页与 ohosTest 共用这一份逻辑，测试走的就是真机上的路径。log 用于真机排查（hilog）。
 */
import { ToastCenter } from './ToastCenter';

export interface UndoableDeleteSteps {
  /** 吐司文案（已本地化）。 */
  message: string;
  hide: () => void;
  unhide: () => void;
  commit: () => Promise<void>;
  onError: (e: Object) => void;
  log?: (msg: string) => void;
}

export class UndoableDelete {
  /** 返回吐司 serial。 */
  static run(toasts: ToastCenter, steps: UndoableDeleteSteps): number {
    const log = (m: string) => {
      if (steps.log !== undefined) {
        steps.log(m);
      }
    };
    steps.hide();
    log('hidden');
    return toasts.show(steps.message, {
      onUndo: () => {
        log('undo ran: unhide, nothing deleted');
        steps.unhide();
      },
      onCommit: () => {
        log('commit ran: deleting');
        steps.commit().then(() => {
          log('deleted');
          steps.unhide();
        }).catch((e: Object) => {
          log('delete failed');
          steps.unhide();
          steps.onError(e);
        });
      }
    });
  }
}
