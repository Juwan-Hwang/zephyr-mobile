/*
 * mihomo-mobile（libzmihomo.so，cgo c-shared）在 VPN 扩展进程里的类型化包装。**桩**：NAPI 胶水还没写，
 * 目前只有 StubMihomoNative（available = false，所有调用抛 core_crashed）。
 *
 * 对应的 C ABI（mihomo-mobile/zmihomo.go 头注释）：
 *   char*   zm_start(home_dir, config_yaml, controller_unix)   // NULL = 成功，否则错误串（zm_free）
 *   char*   zm_reload(config_yaml)
 *   void    zm_stop(void)
 *   int     zm_running(void)
 *   void    zm_traffic(int64_t* up_bps, int64_t* down_bps, int64_t* up_total, int64_t* down_total)
 *   int64_t zm_memory(void)
 *   void    zm_set_memory_limit(int64_t bytes)
 *   void    zm_free_os_memory(void)
 *   char*   zm_url_test(proxies_json, url, timeout_ms, concurrency)   // JSON
 *   char*   zm_logs(int64_t since, min_level, int limit)               // JSON
 *   char*   zm_version(void)
 *   void    zm_free(char*)
 * NAPI 侧约定：返回 char* 的函数由胶水层负责 zm_free；会阻塞的 start / reload / url_test 走 napi_async_work，
 * ArkTS 侧是 Promise；其余同步。错误串原样透传（只进日志，UI 按 ErrorCode 本地化）。
 */
import { ErrorCode } from '../engine/Model';
import { ZephyrError } from '../engine/ZephyrEngine';

export interface MihomoTraffic {
  upBps: number;
  downBps: number;
  upTotal: number;
  downTotal: number;
}

export interface MihomoNative {
  /** libzmihomo.so 及其 NAPI 胶水已加载。false 时 TunBridges.pick 选 SimulatedTunBridge。 */
  readonly available: boolean;
  /** zm_start。resolve undefined = 成功，string = 内核错误串。 */
  start(homeDir: string, configYaml: string, controllerUnix: string): Promise<string | undefined>;
  /** zm_reload：同一 tun fd、新配置。 */
  reload(configYaml: string): Promise<string | undefined>;
  /** zm_stop：同步，返回时内核已停（不关 tun fd，见 TunBridge）。 */
  stop(): void;
  /** zm_running != 0。 */
  running(): boolean;
  traffic(): MihomoTraffic;
  /** zm_memory：mihomo 自报字节数。 */
  memory(): number;
  setMemoryLimit(bytes: number): void;
  freeOSMemory(): void;
  /** zm_url_test，返回 JSON（见 mihomo-mobile/urltest.go）。 */
  urlTest(proxiesJson: string, url: string, timeoutMs: number, concurrency: number): Promise<string>;
  /** zm_logs，返回 JSON（见 mihomo-mobile/logs.go）。 */
  logs(since: number, minLevel: string, limit: number): string;
  version(): string;
}

/** 未打包 / 未实现时的占位：available = false，任何调用都抛 core_crashed（调用方应先看 available）。 */
export class StubMihomoNative implements MihomoNative {
  readonly available: boolean = false;

  private static err(fn: string): ZephyrError {
    return new ZephyrError(ErrorCode.CORE_CRASHED, 'libzmihomo napi not implemented: ' + fn);
  }

  start(homeDir: string, configYaml: string, controllerUnix: string): Promise<string | undefined> {
    return Promise.reject<string | undefined>(StubMihomoNative.err('zm_start'));
  }

  reload(configYaml: string): Promise<string | undefined> {
    return Promise.reject<string | undefined>(StubMihomoNative.err('zm_reload'));
  }

  stop(): void {
    // 没起过就没有可停的；停止路径不抛，保证 onDestroy 能走完。
  }

  running(): boolean {
    return false;
  }

  traffic(): MihomoTraffic {
    const t: MihomoTraffic = { upBps: 0, downBps: 0, upTotal: 0, downTotal: 0 };
    return t;
  }

  memory(): number {
    return 0;
  }

  setMemoryLimit(bytes: number): void {
    throw StubMihomoNative.err('zm_set_memory_limit');
  }

  freeOSMemory(): void {
    // 同 stop：内存告警路径不抛。
  }

  urlTest(proxiesJson: string, url: string, timeoutMs: number, concurrency: number): Promise<string> {
    return Promise.reject<string>(StubMihomoNative.err('zm_url_test'));
  }

  logs(since: number, minLevel: string, limit: number): string {
    throw StubMihomoNative.err('zm_logs');
  }

  version(): string {
    throw StubMihomoNative.err('zm_version');
  }
}

/** 进程内单例。TODO（需真机 + NAPI 胶水）：动态 import 'libzmihomo.so'，成功则换成真实实现。 */
export class Mihomo {
  private static instance: MihomoNative = new StubMihomoNative();

  static get(): MihomoNative {
    return Mihomo.instance;
  }

  /** 测试 / 胶水就绪后注入。 */
  static set(impl: MihomoNative): void {
    Mihomo.instance = impl;
  }
}
