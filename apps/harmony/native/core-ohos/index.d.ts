// libcore_ohos.so 的 ArkTS/TS 类型声明（手写，与 src/lib.rs 保持一致）。
// 用法：import core from 'libcore_ohos.so';

export interface SubscriptionsSummary {
  count: number;
  totalNodes: number;
}

export interface BuildReport {
  total: number;
  skipped: number;
  added: number;
  removed: number;
  kept: number;
  tookMillis: number;
}

/** §15.c 节点漏斗；nodeFunnel 与 §19.a sceneFunnel 共用。保证 underThreshold ≤ reachable ≤ tested ≤ poolSize。 */
export interface NodeFunnel {
  sourceCount: number;
  poolSize: number;
  tested: number;
  reachable: number;
  underThreshold: number;
  thresholdMs: number;
}

/** core-ohos 自身版本。 */
export function version(): string;
/** zephyr-core 链接探针。 */
export function greeting(): string;

export class MobileCore {
  /** dataDir：应用沙箱 filesDir 下的目录；失败抛 Error。 */
  constructor(dataDir: string);
  /** 同步：订阅数与节点总数。 */
  subscriptionsSummary(): SubscriptionsSummary;
  /** 异步：用 mock 生成器建库（0 < scale ≤ 1）。 */
  rebuildMockNodes(scale: number): Promise<BuildReport>;
  /** 同步：全局节点漏斗；maxAgeMillis ≤ 0 不限新鲜度，thresholdMs ≤ 0 按 300。 */
  nodeFunnel(nowMillis: number, maxAgeMillis: number, thresholdMs: number): NodeFunnel;
  /** 同步：场景漏斗（§19.a）；未知 sceneId 抛 Error（SceneNotFound）。 */
  sceneFunnel(sceneId: string, nowMillis: number, maxAgeMillis: number, thresholdMs: number): NodeFunnel;
}
