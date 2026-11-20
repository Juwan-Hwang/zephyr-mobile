/*
 * 首页（对照 Android ui/home HomeScreen / HomeHeader / HomeCards，简化版）：
 * - 状态 + 时长 + 连接开关（经 ConnectionCoordinator：先起 VPN 扩展再 engine.connect）、失败原因；
 * - 模式选择 规则 / 全局 / 直连（engine.setMode）；
 * - 实时上下行速率（engine.traffic）与今日用量；
 * - 当前节点：全局模式 = 全局节点；规则模式 = 各场景当前节点；直连 = 本机网络。点卡片去节点页。
 * 场景卡的换节点 / 预览出口 / 漏斗等交互暂未移植（见 PR #246 待办）。
 */
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZSegmented } from '../components/ZSegmented';
import {
  ConnectionState, ConnectionStatus, ErrorCode, NodeDetail, NodeId, NodeSummary, ProxyMode, Scene,
  TrafficSample, UsageSummary
} from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { VpnState } from '../vpn/VpnController';

const MODES: ProxyMode[] = [ProxyMode.RULE, ProxyMode.GLOBAL, ProxyMode.DIRECT];

@ComponentV2
export struct HomeView {
  @Event onOpenNodes: () => void = () => {};
  @Event onOpenLibrary: () => void = () => {};

  @Local status: ConnectionStatus = ConnectionStatus.DISCONNECTED;
  @Local mode: ProxyMode = ProxyMode.RULE;
  @Local since: number = 0;
  @Local now: number = Date.now();
  @Local errorCode: ErrorCode | undefined = undefined;
  @Local upBps: number = 0;
  @Local downBps: number = 0;
  @Local todayBytes: number = -1;
  @Local globalNode: NodeSummary | undefined = undefined;
  @Local scenes: Scene[] = [];
  @Local simulated: boolean = false;
  @Local busy: boolean = false;

  private services: AppServices = AppServices.get();
  private subs: StreamSub[] = [];
  private ticker: number = -1;
  private globalId: NodeId | undefined = undefined;

  aboutToAppear(): void {
    const engine = this.services.engine;
    this.subs.push(engine.connectionState().subscribe((c: ConnectionState) => this.onConnection(c)));
    this.subs.push(engine.traffic().subscribe((t: TrafficSample) => {
      this.upBps = t.upBps;
      this.downBps = t.downBps;
    }));
    this.subs.push(engine.scenes().subscribe((s: Scene[]) => {
      this.scenes = s;
    }));
    const vpn = this.services.vpn;
    if (vpn !== undefined) {
      this.subs.push(vpn.state().subscribe((v: VpnState) => {
        this.simulated = v.simulated;
      }));
    } else {
      // 预览器：没有 VPN 扩展，连接本来就是模拟的。
      this.simulated = true;
    }
    engine.usageToday().then((u: UsageSummary) => {
      this.todayBytes = u.todayBytes;
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    for (const s of this.subs) {
      s.cancel();
    }
    this.subs = [];
    this.stopTicker();
  }

  private onConnection(c: ConnectionState): void {
    this.status = c.status;
    this.mode = c.mode;
    this.since = c.since ?? 0;
    this.errorCode = c.status === ConnectionStatus.FAILED && c.error !== undefined ? c.error.code : undefined;
    if (c.status === ConnectionStatus.CONNECTED) {
      this.startTicker();
    } else {
      this.stopTicker();
      this.upBps = 0;
      this.downBps = 0;
    }
    if (c.globalNodeId !== this.globalId) {
      this.globalId = c.globalNodeId;
      this.loadGlobal(c.globalNodeId);
    }
  }

  private loadGlobal(id: NodeId | undefined): void {
    if (id === undefined) {
      this.globalNode = undefined;
      return;
    }
    this.services.engine.node(id).then((d: NodeDetail) => {
      if (this.globalId === id) {
        this.globalNode = d.summary;
      }
    }).catch(() => {
      this.globalNode = undefined;
    });
  }

  private startTicker(): void {
    if (this.ticker >= 0) {
      return;
    }
    this.now = Date.now();
    this.ticker = setInterval(() => {
      this.now = Date.now();
    }, 1000);
  }

  private stopTicker(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  private toggle(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.services.connection.toggle().catch(() => {}).finally(() => {
      this.busy = false;
    });
  }

  private setMode(i: number): void {
    this.services.engine.setMode(MODES[i]).catch(() => {});
  }

  private isConnected(): boolean {
    return this.status === ConnectionStatus.CONNECTED;
  }

  private isTransitioning(): boolean {
    return this.status === ConnectionStatus.CONNECTING || this.status === ConnectionStatus.DISCONNECTING;
  }

  private statusColor(): ResourceColor {
    switch (this.status) {
      case ConnectionStatus.CONNECTED:
        return $r('app.color.screen_green');
      case ConnectionStatus.FAILED:
        return $r('app.color.screen_red');
      case ConnectionStatus.CONNECTING:
      case ConnectionStatus.DISCONNECTING:
        return $r('app.color.screen_amber');
      default:
        return $r('app.color.screen_t3');
    }
  }

  @Builder
  header() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Circle({ width: 8, height: 8 }).fill(this.statusColor())
        Text(Labels.status(this.status))
          .fontSize(15)
          .fontColor($r('app.color.screen_t2'))
        if (this.isConnected() && this.since > 0) {
          Text(Format.duration(this.now - this.since))
            .fontSize(15)
            .fontFamily('monospace')
            .fontColor($r('app.color.screen_t3'))
        }
      }

      if (this.errorCode !== undefined) {
        Text(Labels.connectError(this.errorCode))
          .fontSize(14)
          .fontColor($r('app.color.screen_red'))
      }

      Button(this.isConnected() || this.status === ConnectionStatus.DISCONNECTING
        ? $r('app.string.common_disconnect') : $r('app.string.common_connect'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(52)
        .margin({ top: 12 })
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .enabled(!this.isTransitioning() && !this.busy)
        .opacity(this.isTransitioning() ? 0.6 : 1)
        .fontColor(this.isConnected() ? $r('app.color.screen_t1') : $r('app.color.screen_on_primary'))
        .backgroundColor(this.isConnected() ? $r('app.color.screen_s3') : $r('app.color.screen_primary'))
        .onClick(() => this.toggle())

      if (this.simulated && this.isConnected()) {
        Text($r('app.string.hm_home_simulated'))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  rateTile(label: ResourceStr, bps: number, color: ResourceColor) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
      Row({ space: 4 }) {
        Text(Format.rate(bps).value)
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontFamily('monospace')
          .fontColor(color)
        Text(Format.rate(bps).unit + '/s')
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  traffic() {
    ZCard() {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          this.rateTile($r('app.string.hm_home_download'), this.downBps, $r('app.color.color_download'))
          this.rateTile($r('app.string.hm_home_upload'), this.upBps, $r('app.color.screen_up'))
        }
        .width('100%')

        if (this.todayBytes >= 0) {
          Text($r('app.string.home_today_usage', Format.bytesText(this.todayBytes)))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  nodeLine(label: ResourceStr, name: string, latency: number | undefined) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.screen_t3'))
        .constraintSize({ minWidth: 56 })
      Text(name)
        .fontSize(15)
        .fontColor($r('app.color.screen_t1'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (Format.latencyValue(latency) !== undefined) {
        Text(Format.latencyMsText(latency))
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor(Labels.latencyColor(Format.latencyClass(latency)))
      } else if (latency !== undefined) {
        Text($r('app.string.hm_latency_timeout'))
          .fontSize(13)
          .fontColor(Labels.latencyColor(Format.latencyClass(latency)))
      }
    }
    .width('100%')
    .height(32)
  }

  @Builder
  currentNode() {
    ZCard({ onTap: () => this.onOpenNodes() }) {
      Column({ space: 4 }) {
        Text($r('app.string.hm_home_current_node'))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .margin({ bottom: 4 })
        if (this.mode === ProxyMode.DIRECT) {
          Text($r('app.string.common_local_network'))
            .fontSize(15)
            .fontColor($r('app.color.screen_t1'))
        } else if (this.mode === ProxyMode.GLOBAL) {
          if (this.globalNode !== undefined) {
            this.nodeLine($r('app.string.common_mode_global'), this.globalNode.name, this.globalNode.latencyMs)
          } else {
            Text($r('app.string.home_global_body_any'))
              .fontSize(14)
              .fontColor($r('app.color.screen_t2'))
          }
        } else {
          ForEach(this.scenes, (s: Scene) => {
            this.nodeLine(Labels.sceneName(s), s.selected.name, s.selected.latencyMs)
          }, (s: Scene) => s.id + ':' + String(s.selected.id) + ':' + String(s.selected.latencyMs))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text($r('app.string.EntryAbility_label'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.screen_t1'))

        this.header()

        Column({ space: 6 }) {
          ZSegmented({
            options: [Labels.mode(ProxyMode.RULE), Labels.mode(ProxyMode.GLOBAL), Labels.mode(ProxyMode.DIRECT)],
            selected: MODES.indexOf(this.mode),
            onSelect: (i: number) => this.setMode(i)
          })
          Text(Labels.modeHint(this.mode))
            .fontSize(12)
            .fontColor($r('app.color.screen_t3'))
        }
        .alignItems(HorizontalAlign.Start)

        this.traffic()
        this.currentNode()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 24, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
