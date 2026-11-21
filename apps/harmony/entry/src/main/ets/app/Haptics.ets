/*
 * 触感反馈（S11；对照 iOS Haptics / Android performHapticFeedback）。@kit.SensorServiceKit vibrator，需 ohos.permission.VIBRATE。
 * 设备不支持预置效果时静默跳过；任何失败都不影响操作本身。
 */
import { vibrator } from '@kit.SensorServiceKit';

export enum HapticKind {
  /** 选择变化（分段、切换）。 */
  SELECTION = 'haptic.clock.timer',
  /** 破坏性操作确认（删除）。 */
  WARNING = 'haptic.notice.warning',
  /** 操作成功。 */
  SUCCESS = 'haptic.notice.success'
}

export class Haptics {
  static play(kind: HapticKind): void {
    try {
      if (!vibrator.isSupportEffectSync(kind)) {
        return;
      }
      const effect: vibrator.VibratePreset = { type: 'preset', effectId: kind, count: 1 };
      const attr: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };
      vibrator.startVibration(effect, attr).catch(() => {});
    } catch (e) {
      // 无马达 / 无权限：跳过。
    }
  }
}
