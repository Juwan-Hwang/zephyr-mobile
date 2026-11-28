/*
 * UI 侧连接入口（对照 Android ConnectionController）：首页开关 / 以后的卡片、通知都走这里。
 * 平台层先起 VPN 扩展，再由引擎 connect（契约 §11）。扩展在另一个进程，状态经 status.json 回报，这里轮询。
 *
 * - start：写启动意图（active）→ vpnExtension.startVpnExtensionAbility（首次会弹系统授权框）→ STARTING，
 *   等扩展回报 RUNNING / FAILED（超时按失败）。
 * - stop：写意图（active = false，generation +1 让进行中的启动作废）→ stopVpnExtensionAbility → STOPPING → IDLE。
 * - restart：stop 后等 ~500 ms 再 start（VPN 框架 destroy 异步）。
 * - 运行中低频轮询，捕捉系统设置里关掉 VPN / 被别的 VPN 顶掉（扩展 onDestroy 会回报 idle）。
 *
 * 待真机确认：用户拒绝授权时 startVpnExtensionAbility 的错误码。确认前一律报 internal（message 带原始码），
 * 确认后把拒绝码映射到 vpn_permission_denied。
 */
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorCode, ProxyMode, Settings, ZephyrErrorInfo } from '../engine/Model';
import { StateStream } from '../engine/Stream';
import { ZephyrError } from '../engine/ZephyrEngine';
import {
  RECREATE_DELAY_MS, StartIntentInput, StartIntentStore, VPN_ABILITY_NAME, VpnPhase, VpnStatus, VpnStatusStore
} from './StartIntent';

const DOMAIN: number = 0x5A50;
const TAG: string = 'VpnController';
const POLL_FAST_MS: number = 300;
const POLL_SLOW_MS: number = 2000;
const START_TIMEOUT_MS: number = 15000;
const STOP_TIMEOUT_MS: number = 5000;

export interface VpnState {
  phase: VpnPhase;
  /** 当前意图的 generation（0 = 从没启动过）。 */
  generation: number;
  /** 扩展没建 tun（模拟连接）。 */
  simulated: boolean;
  since?: number;
  error?: ZephyrErrorInfo;
}

export interface VpnStartOptions {
  mode: ProxyMode;
  settings: Settings;
  /** 按需连接 / 系统拉起为 true；用户手动为 false。 */
  auto: boolean;
  /** Mock 引擎 / 调试允许无内核的模拟连接；真实引擎传 false。 */
  allowSimulated: boolean;
  excludedApps?: string[];
}

function errorCodeOf(s: string | undefined): ErrorCode {
  switch (s) {
    case 'vpn_permission_denied':
      return ErrorCode.VPN_PERMISSION_DENIED;
    case 'core_crashed':
      return ErrorCode.CORE_CRASHED;
    case 'subscription_not_found':
      return ErrorCode.SUBSCRIPTION_NOT_FOUND;
    case 'subscription_invalid':
      return ErrorCode.SUBSCRIPTION_INVALID;
    case 'network_unavailable':
      return ErrorCode.NETWORK_UNAVAILABLE;
    default:
      return ErrorCode.INTERNAL;
  }
}

export class VpnController {
  private context: common.UIAbilityContext;
  private intents: StartIntentStore;
  private statuses: VpnStatusStore;
  private stateStream: StateStream<VpnState>;
  private timer: number = -1;
  private deadline: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.intents = new StartIntentStore(context.filesDir);
    this.statuses = new VpnStatusStore(context.filesDir);
    const initial: VpnState = { phase: VpnPhase.IDLE, generation: this.intents.generation(), simulated: false };
    this.stateStream = new StateStream<VpnState>(initial);
    // 冷启动 UI 时扩展可能已在跑（上次会话 / 系统拉起）：读一次现状。
    this.syncFromStatus();
  }

  /** 订阅即回放当前值。 */
  state(): StateStream<VpnState> {
    return this.stateStream;
  }

  private want(): Want {
    const w: Want = { bundleName: this.context.applicationInfo.name, abilityName: VPN_ABILITY_NAME };
    return w;
  }

  async start(opts: VpnStartOptions): Promise<void> {
    const input: StartIntentInput = {
      active: true,
      auto: opts.auto,
      mode: opts.mode,
      mtu: opts.settings.tun.mtu,
      ipv6: opts.settings.tun.ipv6,
      excludedApps: opts.excludedApps === undefined ? [] : opts.excludedApps,
      allowSimulated: opts.allowSimulated
    };
    const intent = this.intents.write(input);
    this.set(VpnPhase.STARTING, intent.generation, false, undefined);
    try {
      await vpnExtension.startVpnExtensionAbility(this.want());
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'startVpnExtensionAbility failed: %{public}d', be.code);
      this.intents.deactivate();
      const err = new ZephyrError(ErrorCode.INTERNAL, 'startVpnExtensionAbility: ' + be.code + ' ' + be.message);
      this.set(VpnPhase.FAILED, intent.generation, false, err.toInfo());
      throw err;
    }
    this.deadline = Date.now() + START_TIMEOUT_MS;
    this.poll(POLL_FAST_MS);
  }

  async stop(): Promise<void> {
    const intent = this.intents.deactivate();
    this.set(VpnPhase.STOPPING, intent.generation, this.stateStream.value.simulated, undefined);
    try {
      await vpnExtension.stopVpnExtensionAbility(this.want());
    } catch (e) {
      // 扩展本来就没在跑：直接算断开。
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'stopVpnExtensionAbility failed: %{public}d', be.code);
      this.set(VpnPhase.IDLE, intent.generation, false, undefined);
      return;
    }
    this.deadline = Date.now() + STOP_TIMEOUT_MS;
    this.poll(POLL_FAST_MS);
  }

  async restart(opts: VpnStartOptions): Promise<void> {
    await this.stop();
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, RECREATE_DELAY_MS);
    });
    await this.start(opts);
  }

  /** 页面销毁 / 进程退到后台时停轮询（状态以 status.json 为准，回前台再 syncFromStatus）。 */
  dispose(): void {
    this.cancelPoll();
  }

  /** 读一次 status.json 并合并到状态流；运行中则继续低频轮询。 */
  syncFromStatus(): void {
    const intent = this.intents.read();
    const s = this.statuses.read();
    if (intent === undefined || s === undefined || s.generation !== intent.generation) {
      return;
    }
    this.apply(s);
    if (s.phase === VpnPhase.RUNNING) {
      this.poll(POLL_SLOW_MS);
    }
  }

  private set(phase: VpnPhase, generation: number, simulated: boolean, error: ZephyrErrorInfo | undefined): void {
    const prev = this.stateStream.value;
    const st: VpnState = {
      phase: phase,
      generation: generation,
      simulated: simulated,
      since: phase === VpnPhase.RUNNING ? (prev.phase === VpnPhase.RUNNING && prev.since !== undefined ? prev.since : Date.now()) : undefined,
      error: error
    };
    this.stateStream.value = st;
  }

  private apply(s: VpnStatus): void {
    const prev = this.stateStream.value;
    if (prev.phase === s.phase && prev.generation === s.generation && prev.simulated === s.simulated) {
      return;
    }
    let err: ZephyrErrorInfo | undefined = undefined;
    if (s.phase === VpnPhase.FAILED) {
      const e = new ZephyrError(errorCodeOf(s.errorCode), s.errorMessage);
      err = e.toInfo();
    }
    this.set(s.phase, s.generation, s.simulated, err);
  }

  private cancelPoll(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private poll(interval: number): void {
    this.cancelPoll();
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.tick();
    }, interval);
  }

  private tick(): void {
    const cur = this.stateStream.value;
    const s = this.statuses.read();
    if (s !== undefined && s.generation === cur.generation) {
      this.apply(s);
    }
    const now = this.stateStream.value;
    switch (now.phase) {
      case VpnPhase.STARTING:
      case VpnPhase.STOPPING:
        if (Date.now() > this.deadline) {
          if (now.phase === VpnPhase.STOPPING) {
            this.set(VpnPhase.IDLE, now.generation, false, undefined);
          } else {
            const e = new ZephyrError(ErrorCode.INTERNAL, 'vpn extension did not report in time');
            this.set(VpnPhase.FAILED, now.generation, false, e.toInfo());
          }
          return;
        }
        this.poll(POLL_FAST_MS);
        return;
      case VpnPhase.RUNNING:
        this.poll(POLL_SLOW_MS);
        return;
      default:
        return;
    }
  }
}
