/*
 * 首页（对照 Android ui/home HomeScreen / HomeHeader / HomeCards，简化版）：
 * - 状态 + 时长 + 连接开关（经 ConnectionCoordinator：先起 VPN 扩展再 engine.connect）、失败原因；
 * - 模式选择 规则 / 全局 / 直连（engine.setMode）；
 * - 实时上下行速率（engine.traffic）与今日用量；
 * - 当前节点：全局模式 = 全局节点；直连 = 本机网络。点卡片去节点页。
 * - 规则模式：场景行（U5）：左右滑换地区 → 内联“更改出口 IP？”确认卡（previewSceneChange）→ 更改后 5 s 撤销吐司。
 * - 顶栏：Zephyr + 右上设置；底栏（原型 .dock）：资料库按钮（契约 §17.e，无底部 Tab）。指令栏待指令解析移植后再加。
 * 场景详情 sheet / 漏斗 / 例外等暂未移植（M1-5）。
 */
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZSegmented } from '../components/ZSegmented';
import { SceneRow } from './SceneRow';
import { HapticKind, Haptics } from '../app/Haptics';
import {
  ConnectionState, ConnectionStatus, ErrorCode, ExitChange, NodeDetail, NodeId, NodeSummary, ProxyMode, Scene, ServiceHealth,
  TrafficSample, UsageSummary
} from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { VpnState } from '../vpn/VpnController';
import { ZTerm } from '../generated/ZTerms';

const MODES: ProxyMode[] = [ProxyMode.RULE, ProxyMode.GLOBAL, ProxyMode.DIRECT];

@ComponentV2
export struct HomeView {
  @Event onOpenNodes: () => void = () => {};
  @Event onOpenLibrary: () => void = () => {};
  @Event onOpenSettings: () => void = () => {};

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
  /** 场景行滑动后待确认的出口更改（同一时间一条）。 */
  @Local pendingSceneId: string = '';
  @Local pendingNode: NodeSummary | undefined = undefined;
  @Local pendingChange: ExitChange | undefined = undefined;
  @Local applying: boolean = false;

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

  // ── 场景出口更改（U5）──────────────────────────────────────────────────
  private pick(scene: Scene, node: NodeSummary): void {
    const engine = this.services.engine;
    engine.previewSceneChange(scene.id, node.id).then((c: ExitChange) => {
      this.pendingSceneId = scene.id;
      this.pendingNode = node;
      this.pendingChange = c;
    }).catch(() => {
      this.cancelPending();
    });
  }

  private cancelPending(): void {
    this.pendingSceneId = '';
    this.pendingNode = undefined;
    this.pendingChange = undefined;
  }

  private confirmPending(): void {
    const scene = this.scenes.find((s: Scene) => s.id === this.pendingSceneId);
    const node = this.pendingNode;
    if (scene === undefined || node === undefined || this.applying) {
      return;
    }
    const previous = scene.selected.id;
    const engine = this.services.engine;
    this.applying = true;
    engine.applySceneChange(scene.id, node.id).then(() => {
      Haptics.play(HapticKind.SUCCESS);
      this.cancelPending();
      this.services.toasts.show(this.text($r('app.string.home_switched_to'), node.name), {
        onUndo: () => {
          engine.applySceneChange(scene.id, previous).catch(() => {});
        }
      });
    }).catch(() => {
      this.cancelPending();
    }).finally(() => {
      this.applying = false;
    });
  }

  private text(r: Resource, arg: string): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, arg) : arg;
    } catch (e) {
      return arg;
    }
  }

  private confirmTitle(c: ExitChange, scene: Scene): ResourceStr {
    if (c.affectedApps.length > 0) {
      return $r('app.string.home_confirm_apps', c.affectedApps.join('、'));
    }
    return $r('app.string.home_confirm_scene', scene.name);
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
        ? ZTerm.disconnect : $r('app.string.common_connect'))
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
            this.nodeLine(ZTerm.modeGlobal, this.globalNode.name, this.globalNode.latencyMs)
          } else {
            Text($r('app.string.home_global_body_any'))
              .fontSize(14)
              .fontColor($r('app.color.screen_t2'))
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 原型 .cf：琥珀点 + 标题、等宽“地区 IP → 地区 IP”、保持不变的应用、更改 / 取消。 */
  @Builder
  exitConfirm(scene: Scene, c: ExitChange) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Circle({ width: 6, height: 6 }).fill($r('app.color.screen_amber'))
        Text(this.confirmTitle(c, scene))
          .fontSize(14)
          .fontColor($r('app.color.screen_t1'))
          .layoutWeight(1)
      }
      Row({ space: 8 }) {
        Text(c.fromRegion + ' ' + (c.fromIp ?? '—'))
          .fontSize(12.5)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t2'))
          .maxLines(1)
        Text('→')
          .fontSize(12.5)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t4'))
        Text(c.toRegion + ' ' + (c.toIp ?? '—'))
          .fontSize(12.5)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t1'))
          .maxLines(1)
      }
      if (c.unchangedApps.length > 0) {
        Text($r('app.string.home_confirm_unchanged', c.unchangedApps.join('、')))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
      }
      Row({ space: 8 }) {
        Button($r('app.string.common_change'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_on_primary'))
          .backgroundColor($r('app.color.screen_primary'))
          .enabled(!this.applying)
          .onClick(() => this.confirmPending())
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
          .backgroundColor($r('app.color.screen_hl'))
          .onClick(() => this.cancelPending())
      }
      .margin({ top: 2 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.screen_s3'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sceneRows() {
    Column() {
      ForEach(this.scenes, (s: Scene, i: number) => {
        SceneRow({
          scene: s,
          pendingNode: this.pendingSceneId === s.id ? this.pendingNode : undefined,
          divider: i < this.scenes.length - 1 && this.pendingSceneId !== s.id,
          onPick: (n: NodeSummary) => this.pick(s, n),
          onScrubStart: () => {
            if (this.pendingSceneId !== '') {
              this.cancelPending();
            }
          }
        })
        if (this.pendingSceneId === s.id && this.pendingChange !== undefined) {
          Column() {
            this.exitConfirm(s, this.pendingChange)
          }
          .padding({ left: 16, right: 16, bottom: 14 })
        }
      }, (s: Scene) => s.id + ':' + String(s.selected.id) + ':' + s.source + ':' + String(s.available) + ':' +
        String(s.exceptions.length) + ':' + String(s.services.filter((h: ServiceHealth) => !h.ok).length))
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.screen_s1'))
    .clip(true)
  }

  @Builder
  topBar() {
    Row() {
      Text($r('app.string.EntryAbility_label'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.screen_t1'))
        .accessibilityLevel('yes')
      Blank()
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(22)
          .fontColor([$r('app.color.screen_t2')])
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .accessibilityText(ZTerm.settings)
      .onClick(() => this.onOpenSettings())
    }
    .width('100%')
  }

  /** 底栏（原型 .dock）：右侧资料库按钮；上方渐隐，内容滚到底栏下也看得清。 */
  @Builder
  dock() {
    Column() {
      Row() {
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(22)
            .fontColor([$r('app.color.screen_on_primary')])
        }
        .width(52)
        .height(52)
        .backgroundColor($r('app.color.screen_primary'))
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .accessibilityText($r('app.string.common_library'))
        .onClick(() => this.onOpenLibrary())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.content()
      this.dock()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.screen_bg'))
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: 16 }) {
        this.topBar()

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
        if (this.mode === ProxyMode.RULE && this.scenes.length > 0) {
          this.sceneRows()
        } else {
          this.currentNode()
        }
      }
      .width('100%')
      // 底部留出底栏（52 + 20）+ 间距，最后一张卡不被资料库按钮挡住。
      .padding({ left: 16, right: 16, top: 16, bottom: 96 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
