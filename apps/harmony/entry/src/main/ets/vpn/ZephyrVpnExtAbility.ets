/*
 * VPN 扩展（独立 :vpn 进程）：读启动意图 → 建 tun → 交给 TunBridge（嵌入式 mihomo）。对照 Android ZephyrVpnService。
 *
 * 生命周期：
 * - onCreate：读 StartIntent。无意图 / active = false（用户已断开，却被系统拉起）→ 回报 idle 并自行停止。
 * - 启动：等够上一个实例销毁后 ~500 ms（VPN 框架的 destroy 是异步的，立刻 create 会撞 2203002「VPN 已存在」）→
 *   protectProcessNet（本进程之后建的 socket 绕过隧道）→ create(VpnConfig) 拿 fd → bridge.start(fd)。
 *   每个 await 之后核对 generation：UI 又写了新意图（断开 / 重连）就放弃本轮。
 * - onDestroy：停 bridge → destroy 连接（回收 fd；fd 系统所有，本进程从不 close）→ 回报 idle + destroyedAt。
 *
 * 待办（需真机 / 内核）：运行时配置（core-ohos runtimeConfig）未实现，所以目前 TunBridges.pick 总是 Simulated；
 * 按需连接、受信任 Wi‑Fi、网络切换 closeAll、通知 / 卡片同步都还没接（Android 在 ZephyrVpnService 里）。
 */
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorCode } from '../engine/Model';
import { ZephyrError } from '../engine/ZephyrEngine';
import { Mihomo } from './MihomoNative';
import {
  RECREATE_DELAY_MS, StartIntent, StartIntentStore, VPN_ABILITY_NAME, VpnPhase, VpnStatusStore
} from './StartIntent';
import { RuntimeConfigProvider, SimulatedTunBridge, TunBridge, TunBridges } from './TunBridge';
import { buildVpnConfig } from './VpnConfigBuilder';

const DOMAIN: number = 0x5A50;
const TAG: string = 'ZephyrVpnExt';
/** create 撞上「VPN 已存在」（2203002）时：destroy → 等 RECREATE_DELAY_MS → 再试一次。 */
const ERR_VPN_EXISTS: number = 2203002;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

class Cancelled extends Error {
  constructor() {
    super('superseded');
    this.name = 'Cancelled';
  }
}

export default class ZephyrVpnExtAbility extends VpnExtensionAbility {
  private conn: vpnExtension.VpnConnection | undefined = undefined;
  private bridge: TunBridge = new SimulatedTunBridge();
  private intents: StartIntentStore | undefined = undefined;
  private status: VpnStatusStore | undefined = undefined;
  private generation: number = 0;
  private stopped: boolean = false;
  private simulated: boolean = false;

  /** 运行时配置来源（core-ohos runtimeConfig）。TODO：core-ohos 导出后在此接上；undefined → Simulated。 */
  private configProvider: RuntimeConfigProvider | undefined = undefined;

  onCreate(want: Want): void {
    const filesDir = this.context.filesDir;
    this.intents = new StartIntentStore(filesDir);
    this.status = new VpnStatusStore(filesDir);
    const intent = this.intents.read();
    if (intent === undefined || !intent.active) {
      hilog.info(DOMAIN, TAG, 'no active start intent; stopping');
      this.report(intent === undefined ? 0 : intent.generation, VpnPhase.IDLE);
      this.stopSelf();
      return;
    }
    this.generation = intent.generation;
    this.report(intent.generation, VpnPhase.STARTING);
    this.start(intent).catch((e: Error) => {
      if (e instanceof Cancelled || this.stopped) {
        hilog.info(DOMAIN, TAG, 'start superseded (gen %{public}d)', intent.generation);
        return;
      }
      const ze = ZephyrError.from(e);
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s %{public}s', ze.code, ze.message);
      this.teardown().finally(() => {
        this.report(intent.generation, VpnPhase.FAILED, ze.code, ze.message);
        this.stopSelf();
      });
    });
  }

  onDestroy(): void {
    this.stopped = true;
    const gen = this.generation;
    this.teardown().finally(() => {
      this.report(gen, VpnPhase.IDLE, undefined, undefined, Date.now());
    });
  }

  private async start(intent: StartIntent): Promise<void> {
    await this.waitRecreateGap();
    this.check(intent.generation);

    const filesDir = this.context.filesDir;
    this.bridge = TunBridges.pick(Mihomo.get(), TunBridges.homeDir(filesDir), this.configProvider);
    if (!this.bridge.createsTun) {
      if (!intent.allowSimulated) {
        // Release 不装：没有隧道就不能显示“已连接”而流量直连。
        throw new ZephyrError(ErrorCode.CORE_CRASHED, 'native core not packaged');
      }
      this.simulated = true;
      hilog.warn(DOMAIN, TAG, 'simulated tunnel (no core); no tun created');
      this.report(intent.generation, VpnPhase.RUNNING);
      return;
    }

    const conn = vpnExtension.createVpnConnection(this.context);
    this.conn = conn;
    // 本进程（ArkTS / libc / 内核）之后建的 socket 都绕过隧道，免得内核出站又进 tun。
    await conn.protectProcessNet();
    this.check(intent.generation);

    const fd = await this.createTun(conn, buildVpnConfig(intent, this.context.applicationInfo.name));
    this.check(intent.generation);
    hilog.info(DOMAIN, TAG, 'tun created fd=%{public}d', fd);

    const err = await this.bridge.start(fd);
    this.check(intent.generation);
    if (err !== undefined) {
      throw new ZephyrError(ErrorCode.CORE_CRASHED, err);
    }
    this.report(intent.generation, VpnPhase.RUNNING);
  }

  private async createTun(conn: vpnExtension.VpnConnection, cfg: vpnExtension.VpnConfig): Promise<number> {
    try {
      return await conn.create(cfg);
    } catch (e) {
      const be = e as BusinessError;
      if (be.code !== ERR_VPN_EXISTS) {
        throw new ZephyrError(ErrorCode.INTERNAL, 'vpn create failed: ' + be.code + ' ' + be.message);
      }
      hilog.warn(DOMAIN, TAG, 'vpn exists; destroy and retry once');
      try {
        await conn.destroy();
      } catch (ignored) {
        // 再试一次 create，失败就照常报错。
      }
      await sleep(RECREATE_DELAY_MS);
      return await conn.create(cfg);
    }
  }

  /** 上一个实例 destroyedAt 距今不足 RECREATE_DELAY_MS 时补足。 */
  private async waitRecreateGap(): Promise<void> {
    const s = this.status === undefined ? undefined : this.status.read();
    if (s === undefined || s.destroyedAt === undefined) {
      return;
    }
    const wait = s.destroyedAt + RECREATE_DELAY_MS - Date.now();
    if (wait > 0 && wait <= RECREATE_DELAY_MS) {
      await sleep(wait);
    }
  }

  /** 被新意图取代（或已销毁）就中止本轮启动。 */
  private check(gen: number): void {
    if (this.stopped || gen !== this.generation) {
      throw new Cancelled();
    }
    const cur = this.intents === undefined ? undefined : this.intents.read();
    if (cur === undefined || cur.generation !== gen || !cur.active) {
      throw new Cancelled();
    }
  }

  private async teardown(): Promise<void> {
    this.bridge.stop();
    this.bridge = new SimulatedTunBridge();
    const conn = this.conn;
    this.conn = undefined;
    if (conn !== undefined) {
      try {
        await conn.destroy();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'vpn destroy failed');
      }
    }
  }

  private report(gen: number, phase: VpnPhase, code?: string, message?: string, destroyedAt?: number): void {
    if (this.status === undefined) {
      return;
    }
    try {
      this.status.write(gen, phase, this.simulated, code, message, destroyedAt);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'status write failed');
    }
  }

  private stopSelf(): void {
    const want: Want = { bundleName: this.context.applicationInfo.name, abilityName: VPN_ABILITY_NAME };
    vpnExtension.stopVpnExtensionAbility(want).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'stopVpnExtensionAbility failed: %{public}d', e.code);
    });
  }
}
