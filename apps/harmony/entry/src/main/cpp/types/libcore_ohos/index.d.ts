// 拷贝自 apps/harmony/native/core-ohos/index.d.ts（分支 agent/d/core-ohos），两边同步修改。
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
}
