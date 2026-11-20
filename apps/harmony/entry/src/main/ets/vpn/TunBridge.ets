/*
 * 把 tun fd 交给内核（对照 Android TunBridge.kt）。mihomo 以库形式嵌在 VPN 扩展进程里（libzmihomo.so），
 * 直接从 fd 读包：没有子进程，也没有回环 socks 跳转。
 *
 * fd 归属：VpnConnection.create() 返回的 fd 属于系统 VPN 框架（鸿蒙没有 ParcelFileDescriptor 可 close），
 * 由 VpnConnection.destroy() 回收。桥和内核都 **不得 close 它**：stop() 只停内核；生成给 mihomo 的配置里
 * tun.file-descriptor 指向它，mihomo 停止时也不能关（core-ohos 的 runtimeConfig 负责置位，待实现）。
 */
import { fileIo } from '@kit.CoreFileKit';
import { MihomoNative } from './MihomoNative';

/**
 * 生成运行时配置：活动订阅 + Zephyr 设置 + tun fd，控制面走私有 unix socket（Android CoreEngine.runtimeConfig
 * 的等价物）。resolve undefined = 没有活动订阅。由 core-ohos 提供，目前没有实现（见 ZephyrVpnExtAbility）。
 */
export type RuntimeConfigProvider = (tunFd: number, controllerUnix: string) => Promise<string | undefined>;

export interface TunBridge {
  /** true = 真会承载流量，因此需要真实 tun；false 时扩展不建 tun（建了没人读会把流量黑洞掉）。 */
  readonly createsTun: boolean;
  readonly name: string;
  /** resolve undefined = 成功，string = 错误信息（只进日志）。fd 为系统所有，不得关闭。 */
  start(tunFd: number): Promise<string | undefined>;
  /** 幂等；不抛（onDestroy 路径）。 */
  stop(): void;
}

/** 没有内核 / 没有订阅：UI 流程能走通，不建 tun。只在 StartIntent.allowSimulated 时允许“已连接”。 */
export class SimulatedTunBridge implements TunBridge {
  readonly createsTun: boolean = false;
  readonly name: string = 'simulated';

  start(tunFd: number): Promise<string | undefined> {
    return Promise.resolve<string | undefined>(undefined);
  }

  stop(): void {
    // 无事可做。
  }
}

/** 真实路径：runtimeConfig(fd) → zm_start。mihomo 直接从 fd 读包。 */
export class NativeTunBridge implements TunBridge {
  readonly createsTun: boolean = true;
  readonly name: string = 'native';
  private mihomo: MihomoNative;
  private homeDir: string;
  private config: RuntimeConfigProvider;
  private started: boolean = false;

  constructor(mihomo: MihomoNative, homeDir: string, config: RuntimeConfigProvider) {
    this.mihomo = mihomo;
    this.homeDir = homeDir;
    this.config = config;
  }

  async start(tunFd: number): Promise<string | undefined> {
    if (tunFd < 0) {
      return 'invalid tun fd ' + tunFd;
    }
    const sock = TunBridges.controllerSocket(this.homeDir);
    let cfg: string | undefined;
    try {
      cfg = await this.config(tunFd, sock);
    } catch (e) {
      return e instanceof Error ? (e as Error).message : 'runtime config failed';
    }
    if (cfg === undefined) {
      return 'no active subscription';
    }
    try {
      this.mihomo.setMemoryLimit(TunBridges.MEMORY_LIMIT);
      // 上次崩溃留下的 socket 会让监听失败。
      if (fileIo.accessSync(sock)) {
        fileIo.unlinkSync(sock);
      }
      const err = await this.mihomo.start(this.homeDir, cfg, sock);
      this.started = err === undefined;
      return err;
    } catch (e) {
      return e instanceof Error ? (e as Error).message : 'zm_start failed';
    }
  }

  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    try {
      this.mihomo.stop();
      this.mihomo.freeOSMemory();
    } catch (e) {
      // stop 路径不抛。
    }
  }
}

export class TunBridges {
  /** VPN 进程的 Go 软上限（与 Android 相同：核心稳态 ≤ 60 MB RSS）。 */
  static readonly MEMORY_LIMIT: number = 48 * 1024 * 1024;
  static readonly MTU_MIN: number = 1280;
  static readonly MTU_MAX: number = 9000;
  /** tun 参数与核心配置共享（fake-ip 198.18.0.0/15，同桌面 TUN）。 */
  static readonly TUN_ADDRESS4: string = '198.18.0.1';
  static readonly TUN_PREFIX4: number = 30;
  static readonly TUN_DNS: string = '198.18.0.2';
  static readonly TUN_ADDRESS6: string = 'fdfe:dcba:9876::1';
  static readonly TUN_PREFIX6: number = 126;

  /** audit E16：与 iOS / Android 同样夹到 [1280, 9000]；非有限数按 1500。 */
  static clampMtu(mtu: number): number {
    if (!Number.isFinite(mtu)) {
      return 1500;
    }
    return Math.min(TunBridges.MTU_MAX, Math.max(TunBridges.MTU_MIN, Math.round(mtu)));
  }

  /** mihomo home 目录下的控制 socket；zm_start 与 REST 客户端同一路径。 */
  static controllerSocket(homeDir: string): string {
    return homeDir + '/ctl.sock';
  }

  /** mihomo home：filesDir/mihomo（不存在则建）。 */
  static homeDir(filesDir: string): string {
    const d = filesDir + '/mihomo';
    if (!fileIo.accessSync(d)) {
      fileIo.mkdirSync(d, true);
    }
    return d;
  }

  /** 内核可用且有配置来源 → Native；否则 Simulated（调用方再按 allowSimulated 决定是否算失败）。 */
  static pick(mihomo: MihomoNative, homeDir: string, config: RuntimeConfigProvider | undefined): TunBridge {
    if (mihomo.available && config !== undefined) {
      return new NativeTunBridge(mihomo, homeDir, config);
    }
    return new SimulatedTunBridge();
  }
}
