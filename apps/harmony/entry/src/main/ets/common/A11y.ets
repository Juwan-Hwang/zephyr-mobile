/* 读屏状态（§16.e⑥ 撤销窗口延长、吐司朗读）。取不到时按关闭处理。 */
import { accessibility } from '@kit.AccessibilityKit';

export function screenReaderOn(): boolean {
  try {
    return accessibility.isScreenReaderOpenSync();
  } catch (e) {
    return false;
  }
}
