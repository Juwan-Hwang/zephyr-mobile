/*
 * 最近连接（M1-8 / U11，原型 actSheet；对照 Android ui/activity/ActivitySheet.kt + CloseHost.kt、
 * iOS Activity/ActivitySheet + RecentHostRow）的纯逻辑：
 * - 契约 §16.e⑧（U28）：recentHosts(50) = 按域名聚合、最新在前，最多 50 条（原型的 5 条是演示数据）。
 * - 行副标题：没有场景 = 直连；否则 应用 · 场景 · 节点（应用未知时省略；内置场景名随应用语言）。
 * - 所有行都不知道应用时，列表下加脚注“暂不知道发起连接的应用……”（同 Android activity_no_app_note）。
 * - 长按关闭该域名的活动连接（iOS H-P2-14 / Android closeHostConnections）：取 activeConnections 的第一帧，
 *   逐个 closeConnection，结果 → 吐司文案种类。
 * 不依赖 ArkUI，node / ohosTest 可测。
 */
import { ConnectionInfo } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export const RECENT_HOSTS_MAX: number = 50;
/** activeConnections 迟迟不出第一帧时放弃（真引擎未连接时可能不推）。 */
export const CLOSE_HOST_WAIT_MS: number = 2000;

export enum CloseOutcome {
  /** 没有活动的连接。 */
  NONE = 'none',
  /** 全部关闭：已关闭 n 个连接。 */
  CLOSED = 'closed',
  /** 全部失败：连接未能关闭（n = 总数）。 */
  FAILED = 'failed',
  /** 部分失败：n 个连接未能关闭（n = 失败数）。 */
  PARTIAL = 'partial'
}

export class CloseResult {
  outcome: CloseOutcome;
  /** 文案里的数字（复数选择用）。 */
  count: number;

  constructor(outcome: CloseOutcome, count: number) {
    this.outcome = outcome;
    this.count = count;
  }
}

export class RecentHostsModel {
  /** 同 Android closeMessage。 */
  static closeResult(closed: number, total: number): CloseResult {
    if (total === 0) {
      return new CloseResult(CloseOutcome.NONE, 0);
    }
    if (closed === total) {
      return new CloseResult(CloseOutcome.CLOSED, closed);
    }
    if (closed === 0) {
      return new CloseResult(CloseOutcome.FAILED, total);
    }
    return new CloseResult(CloseOutcome.PARTIAL, total - closed);
  }

  /** 直连行（没有场景）。 */
  static isDirect(c: ConnectionInfo): boolean {
    return c.scene === undefined;
  }

  /** 副标题各段（直连行返回空表，由界面显示“直连”）。sceneLabel：已本地化的场景名。 */
  static subtitleParts(c: ConnectionInfo, sceneLabel: string): string[] {
    if (RecentHostsModel.isDirect(c)) {
      return [];
    }
    const out: string[] = [];
    if (c.app !== undefined && c.app.length > 0) {
      out.push(c.app);
    }
    if (sceneLabel.length > 0) {
      out.push(sceneLabel);
    }
    if (c.node.length > 0) {
      out.push(c.node);
    }
    return out;
  }

  static totalBytes(c: ConnectionInfo): number {
    return c.downBytes + c.upBytes;
  }

  /** 列表非空且每行都不知道应用 → 显示脚注。 */
  static showsNoAppNote(list: ConnectionInfo[]): boolean {
    return list.length > 0 && list.every((c: ConnectionInfo) => c.app === undefined || c.app.length === 0);
  }

  /** activeConnections 的第一帧（超时 → 空表）。 */
  static firstActive(engine: ZephyrEngine, waitMs?: number): Promise<ConnectionInfo[]> {
    return new Promise<ConnectionInfo[]>((resolve: (v: ConnectionInfo[]) => void) => {
      let done = false;
      let sub: StreamSub | undefined = undefined;
      let timer = -1;
      const finish = (v: ConnectionInfo[]): void => {
        if (done) {
          return;
        }
        done = true;
        if (timer >= 0) {
          clearTimeout(timer);
          timer = -1;
        }
        // 流可能在 subscribe 返回前就同步推了第一帧：sub 还没赋值，留到下面取消。
        if (sub !== undefined) {
          sub.cancel();
        }
        resolve(v);
      };
      try {
        sub = engine.activeConnections().subscribe((v: ConnectionInfo[]): void => finish(v));
      } catch (e) {
        finish([]);
        return;
      }
      if (done) {
        sub.cancel();
        return;
      }
      timer = setTimeout((): void => finish([]), waitMs ?? CLOSE_HOST_WAIT_MS);
    });
  }

  /** 关闭 host 的全部活动连接，返回吐司结果。 */
  static async closeHost(engine: ZephyrEngine, host: string, waitMs?: number): Promise<CloseResult> {
    const active = await RecentHostsModel.firstActive(engine, waitMs);
    const ids: string[] = active.filter((c: ConnectionInfo) => c.host === host).map((c: ConnectionInfo) => c.id);
    let closed = 0;
    for (const id of ids) {
      try {
        await engine.closeConnection(id);
        closed++;
      } catch (e) {
        // 计入失败数
      }
    }
    return RecentHostsModel.closeResult(closed, ids.length);
  }
}
