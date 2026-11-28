/*
 * 首页开关背后的连接编排（对照 Android ConnectionController）：契约 §11 平台层先起 VPN 扩展，再 engine.connect。
 * - connect：读当前模式与设置 → vpn.start → 等扩展回报 RUNNING → engine.connect；扩展 FAILED / 超时 →
 *   engine.reportConnectFailure，让首页按错误码显示原因。engine.connect 自己失败（如没有订阅）→ 停掉扩展并回报。
 * - disconnect：engine.disconnect → vpn.stop。
 * - 运行中扩展自己变 IDLE（系统设置里关掉 VPN、被别的 VPN 顶掉）→ engine.disconnect，开关跟着回到“未连接”。
 * vpn 为 undefined（DevEco 预览器没有 UIAbility）时只驱动引擎，界面照常可点。
 */
import { ConnectionStatus, ErrorCode, ZephyrErrorInfo } from '../engine/Model';
import { EventStream, Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine, ZephyrError } from '../engine/ZephyrEngine';
import { VpnPhase } from '../vpn/StartIntent';
import { VpnController, VpnState } from '../vpn/VpnController';

function errorFromInfo(info: ZephyrErrorInfo | undefined): ZephyrError {
  if (info === undefined) {
    return new ZephyrError(ErrorCode.INTERNAL, 'vpn failed');
  }
  return new ZephyrError(info.code, info.message);
}

export class ConnectionCoordinator {
  private engine: ZephyrEngine;
  private vpn: VpnController | undefined;
  private vpnSub: StreamSub | undefined = undefined;
  /** 等扩展回报的那次启动的 generation；0 = 没在等。 */
  private pendingGeneration: number = 0;
  private wasRunning: boolean = false;
  private busy: boolean = false;

  constructor(engine: ZephyrEngine, vpn: VpnController | undefined) {
    this.engine = engine;
    this.vpn = vpn;
    if (vpn !== undefined) {
      this.vpnSub = vpn.state().subscribe((s: VpnState) => this.onVpnState(s));
    }
  }

  get hasVpn(): boolean {
    return this.vpn !== undefined;
  }

  /** 首页开关：连接中 / 断开中忽略重复点击。 */
  async toggle(): Promise<void> {
    const st = this.engine.connectionState().value.status;
    if (st === ConnectionStatus.CONNECTED) {
      await this.disconnect();
    } else if (st === ConnectionStatus.DISCONNECTED || st === ConnectionStatus.FAILED) {
      await this.connect();
    }
  }

  /** §16.b②：没有订阅时连接改为打开导入（订阅页展开“添加订阅”），不起 VPN、不弹授权。值无意义，只是事件。 */
  readonly importRequests: EventStream<number> = new EventStream<number>();

  /** 同 Android ConnectionController.hasNoSubscription：取不到时按“有”处理（照常连接）。 */
  async hasNoSubscription(): Promise<boolean> {
    try {
      return (await this.engine.subscriptionsSummary()).count === 0;
    } catch (e) {
      return false;
    }
  }

  async connect(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (await this.hasNoSubscription()) {
      this.importRequests.emit(1);
      return;
    }
    this.busy = true;
    try {
      const vpn = this.vpn;
      if (vpn === undefined) {
        await this.engine.connect();
        return;
      }
      const mode = this.engine.connectionState().value.mode;
      const settings = this.engine.settings().value;
      await vpn.start({ mode: mode, settings: settings, auto: false, allowSimulated: this.engine.kind === 'mock' });
      const gen = vpn.state().value.generation;
      if (vpn.state().value.phase === VpnPhase.RUNNING) {
        await this.engineConnect();
      } else {
        this.pendingGeneration = gen;
      }
    } catch (e) {
      this.engine.reportConnectFailure(ZephyrError.from(e as Object));
    } finally {
      this.busy = false;
    }
  }

  async disconnect(): Promise<void> {
    this.pendingGeneration = 0;
    try {
      await this.engine.disconnect();
    } finally {
      if (this.vpn !== undefined) {
        await this.vpn.stop();
      }
    }
  }

  dispose(): void {
    if (this.vpnSub !== undefined) {
      this.vpnSub.cancel();
      this.vpnSub = undefined;
    }
  }

  private async engineConnect(): Promise<void> {
    try {
      await this.engine.connect();
    } catch (e) {
      const err = ZephyrError.from(e as Object);
      if (this.vpn !== undefined) {
        await this.vpn.stop();
      }
      this.engine.reportConnectFailure(err);
    }
  }

  private onVpnState(s: VpnState): void {
    const running = s.phase === VpnPhase.RUNNING;
    if (this.pendingGeneration !== 0 && s.generation === this.pendingGeneration) {
      if (running) {
        this.pendingGeneration = 0;
        this.engineConnect();
      } else if (s.phase === VpnPhase.FAILED) {
        this.pendingGeneration = 0;
        this.engine.reportConnectFailure(errorFromInfo(s.error));
      }
    } else if (this.wasRunning && s.phase === VpnPhase.IDLE) {
      // 扩展被系统 / 别的 VPN 停掉：引擎跟着断开。
      const st = this.engine.connectionState().value.status;
      if (st === ConnectionStatus.CONNECTED || st === ConnectionStatus.CONNECTING) {
        this.engine.disconnect();
      }
    }
    this.wasRunning = running;
  }
}
