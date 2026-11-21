/*
 * 指令“应用”的执行（契约 §16.d / §16.e⑥；对照 Android AppRoot：CommandOverlay 的 onAction 先 command = false 关面板，
 * 再交给 HomeViewModel.applyCommand 在首页作用域里执行并出吐司）。
 * 鸿蒙之前在面板里 await 引擎、成功后才关面板：真机（Mate 90，云调试 ~290 ms 延迟）上点“应用”后面板还停着、没有反馈，
 * 用户再点一次时面板恰好关掉，这一下落到首页第一行场景（AI）上，打开了 AI 场景 sheet；成功吐司又被仍在的 sheet 盖住。
 * 现在：先同步关面板（close），再执行，结果吐司（带撤销）在首页上出现；失败出“未能应用”吐司。
 * 首页在面板关闭后 GHOST_TAP_MS 内忽略场景行点按（suppressesTap），防同一类“幽灵点按”。
 * 纯逻辑，node / ohosTest 可测。
 */
import { CommandPlan, CommandPlanner } from './CommandPlanner';
import { ToastCenter } from './ToastCenter';

/** 面板关闭后忽略首页点按的时长（sheet 收起动画 ~250 ms + 余量）。 */
export const GHOST_TAP_MS: number = 600;

export interface CommandApplyTexts {
  success: string;
  failed: string;
}

export class CommandApplier {
  /** 先 close()，再 planner.apply；返回是否成功。 */
  static async run(planner: CommandPlanner, plan: CommandPlan, toasts: ToastCenter, texts: CommandApplyTexts,
    close: () => void, onSuccess?: () => void): Promise<boolean> {
    close();
    try {
      const undo: () => Promise<void> = await planner.apply(plan);
      if (onSuccess !== undefined) {
        onSuccess();
      }
      toasts.show(texts.success, {
        onUndo: () => {
          undo().catch(() => {});
        }
      });
      return true;
    } catch (e) {
      toasts.show(texts.failed);
      return false;
    }
  }

  /** closedAt：面板最近一次关闭的时间（ms，0 = 从未）。 */
  static suppressesTap(closedAt: number, now: number): boolean {
    return closedAt > 0 && now >= closedAt && now - closedAt < GHOST_TAP_MS;
  }
}
