/*
 * 横滑手势锁：首页场景行左右滑（SceneRow PanGesture）期间及松手后一小段时间内为 true。
 * 根页面 Tabs.onContentWillChange 据此拒绝切 tab，防止横滑被外层 Tabs / 系统手势带去“节点”页（真机 AGC 云调试复现）。
 */
const RELEASE_GRACE_MS: number = 350;

export class GestureLock {
  private static holding: boolean = false;
  private static releasedAt: number = 0;

  static hold(): void {
    GestureLock.holding = true;
  }

  static release(): void {
    if (GestureLock.holding) {
      GestureLock.holding = false;
      GestureLock.releasedAt = Date.now();
    }
  }

  static active(now?: number): boolean {
    if (GestureLock.holding) {
      return true;
    }
    const t = now ?? Date.now();
    return t - GestureLock.releasedAt < RELEASE_GRACE_MS;
  }
}
