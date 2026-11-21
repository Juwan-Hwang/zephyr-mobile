/*
 * 订阅页纯逻辑（M1-11，U19–U21；对照 Android ui/subs SubscriptionWarning / SubscriptionReview / SubscriptionsScreen，
 * iOS SubscriptionsModel）：
 * - SubscriptionWarning（契约 §16.e④）：已过期或 ≤ 7 个本地日历日内到期，或 used / total ≥ 80% → 琥珀色（订阅页与首页同一规则）；
 *   没有总量（或为 0）不判用量。
 * - UpdateReview（“更新前显示更改”，U19）：单个 = previewUpdate；全部 = 每个订阅预览（最多 6 个并发，同 iOS），
 *   跳过失败，差异相加（覆写全部保留才算保留、任一重新检测即重新检测）；全都失败 → undefined。
 * - 分组（U20）：有流量信息（totalBytes / remainingBytes 任一）的订阅逐行列出，其余并入“其他 N 个 ›”；
 *   summary.count 大于列表长度（引擎只给摘要的订阅）也算进“其他”，节点数用 summary.totalNodes 补差。
 */
import { Subscription, SubscriptionDiff, SubscriptionsSummary } from '../engine/Model';
import { ZephyrEngine } from '../engine/ZephyrEngine';
import { Format } from '../common/Format';

export const WARNING_DAYS: number = 7;
export const WARNING_USED_FRACTION: number = 0.8;
export const PREVIEW_CONCURRENCY: number = 6;

export class SubscriptionWarning {
  static isWarning(s: Subscription, now: number): boolean {
    return SubscriptionWarning.expiresSoon(s.expiresAt, now) || SubscriptionWarning.mostlyUsed(s.usedBytes, s.totalBytes);
  }

  static expiresSoon(expiresAt: number | undefined, now: number): boolean {
    if (expiresAt === undefined) {
      return false;
    }
    if (expiresAt <= now) {
      return true;
    }
    return Format.localDay(expiresAt) - Format.localDay(now) <= WARNING_DAYS;
  }

  static mostlyUsed(used: number | undefined, total: number | undefined): boolean {
    if (used === undefined || total === undefined || total <= 0) {
      return false;
    }
    return used / total >= WARNING_USED_FRACTION;
  }
}

export enum ReviewKind {
  ONE = 'one',
  ALL = 'all'
}

export interface UpdateReview {
  kind: ReviewKind;
  /** ONE：要更新的订阅。 */
  sub?: Subscription;
  /** ALL：成功预览的订阅数。 */
  count: number;
  diff: SubscriptionDiff;
}

export interface SubscriptionGroups {
  metered: Subscription[];
  /** “其他 N 个”的 N（0 = 不显示该行）。 */
  others: number;
  otherNodes: number;
}

export class SubscriptionsModel {
  static one(sub: Subscription, diff: SubscriptionDiff): UpdateReview {
    const r: UpdateReview = { kind: ReviewKind.ONE, sub: sub, count: 1, diff: diff };
    return r;
  }

  static sum(diffs: SubscriptionDiff[]): SubscriptionDiff {
    const d: SubscriptionDiff = {
      addedNodes: 0, removedNodes: 0, ruleChanges: 0, overridesKept: true, scenesRetested: false
    };
    for (const x of diffs) {
      d.addedNodes += x.addedNodes;
      d.removedNodes += x.removedNodes;
      d.ruleChanges += x.ruleChanges;
      d.overridesKept = d.overridesKept && x.overridesKept;
      d.scenesRetested = d.scenesRetested || x.scenesRetested;
    }
    return d;
  }

  /** 全部预览：PREVIEW_CONCURRENCY 个一批，失败的跳过。 */
  static async previewAll(engine: ZephyrEngine): Promise<UpdateReview | undefined> {
    const subs = engine.subscriptions().value;
    const diffs: SubscriptionDiff[] = [];
    for (let i = 0; i < subs.length; i += PREVIEW_CONCURRENCY) {
      const batch = subs.slice(i, i + PREVIEW_CONCURRENCY);
      const got = await Promise.all(batch.map((s: Subscription) => engine.previewUpdate(s.id)
        .then((d: SubscriptionDiff): SubscriptionDiff | undefined => d)
        .catch((): SubscriptionDiff | undefined => undefined)));
      for (const d of got) {
        if (d !== undefined) {
          diffs.push(d);
        }
      }
    }
    if (diffs.length === 0) {
      return undefined;
    }
    const r: UpdateReview = { kind: ReviewKind.ALL, count: diffs.length, diff: SubscriptionsModel.sum(diffs) };
    return r;
  }

  static isMetered(s: Subscription): boolean {
    return s.totalBytes !== undefined || s.remainingBytes !== undefined;
  }

  static groups(subs: Subscription[], summary: SubscriptionsSummary | undefined): SubscriptionGroups {
    const metered = subs.filter((s: Subscription) => SubscriptionsModel.isMetered(s));
    const unmetered = subs.filter((s: Subscription) => !SubscriptionsModel.isMetered(s));
    const listed = summary !== undefined ? Math.max(0, summary.count - subs.length) : 0;
    let nodes = 0;
    let allNodes = 0;
    for (const s of unmetered) {
      nodes += s.nodeCount;
    }
    for (const s of subs) {
      allNodes += s.nodeCount;
    }
    const unlisted = listed > 0 && summary !== undefined ? Math.max(0, summary.totalNodes - allNodes) : 0;
    const g: SubscriptionGroups = { metered: metered, others: unmetered.length + listed, otherNodes: nodes + unlisted };
    return g;
  }

  /** 流量条比例（0–1；没有总量为 0）。 */
  static usedFraction(s: Subscription): number {
    const u = s.usedBytes;
    const t = s.totalBytes;
    return u !== undefined && t !== undefined && t > 0 ? Math.min(1, u / t) : 0;
  }

  /** 最近一次更新的差异卡：第一个带 lastDiff 的订阅。 */
  static lastDiff(subs: Subscription[]): Subscription | undefined {
    return subs.find((s: Subscription) => s.lastDiff !== undefined);
  }
}
