/*
 * libcore_ohos.so 的唯一静态 import 点。其他代码一律经 NativeEngine.create() 动态 import 本文件，
 * 这样 .so 没打包（entry/libs/<abi>/ 为空）时只是 create() 失败，不会拖垮引用方模块的加载。
 */
import core from 'libcore_ohos.so';
import type { MobileCore } from 'libcore_ohos.so';

/** .so 加载成功且导出了预期符号。缺库时 NAPI 默认导出为 undefined。 */
export function coreAvailable(): boolean {
  return core !== undefined && core !== null && typeof core.version === 'function';
}

export function coreVersion(): string {
  return core.version();
}

export function openCore(dataDir: string): MobileCore {
  return new core.MobileCore(dataDir);
}
