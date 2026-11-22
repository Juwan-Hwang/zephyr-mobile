/*
 * 首页（对照 Android ui/home HomeScreen / HomeHeader / HomeCards，简化版）：
 * - 状态 + 时长 + 连接开关（经 ConnectionCoordinator：先起 VPN 扩展再 engine.connect）、失败原因；
 * - 模式选择 规则 / 全局 / 直连（engine.setMode）；
 * - 实时上下行速率（engine.traffic）与今日用量；已连接时点速率区打开最近连接（ActivitySheet，M1-8）；
 * - 当前节点：全局模式 = 全局节点；直连 = 本机网络。点卡片去节点页。
 * - 规则模式：场景行（U5）：左右滑换地区 → 内联“更改出口 IP？”确认卡（previewSceneChange）→ 更改后 5 s 撤销吐司。
 * - 顶栏：Zephyr + 右上设置；底栏（原型 .dock）：左侧指令栏“搜索或输入指令”（点开 CommandSheet，M1-7b）+ 右侧资料库按钮（契约 §17.e，无底部 Tab）。
 * - 场景详情 sheet（M1-5，SceneSheet）：点场景行打开；资料库“场景”入口经 Index 递增 sceneRequest 打开第一个场景
 *   （同 Android AppRoot LibraryDest.Scenes）。sheet 里点候选 → 收起 sheet，首页出同一张“更改出口 IP？”确认卡。
 * - M1-6（U4 / U6 / U7 / U8；同 Android HomeScreen / HomeCards / HomeViewModel，iOS GlobalModeCard / TrafficPanel /
 *   SubscriptionsSection / AppModel+Streams）：
 *   · 流量曲线：已连接时速率下方画最近 90 秒下行曲线（recentTraffic(90) 回填，之后每个样本推进），未连接画虚线基线；
 *   · “场景”小标题，右侧扫描进度 / “x 分钟前检测”（全局模式不显示）；
 *   · 全局模式卡替代场景行：“所有流量均经由 X。场景已暂停。”、使用规则模式 / 更换节点；更换节点展开内联建议
 *     （延迟最低的另一个节点，出口 IP 行 previewGlobalChange）→“更改为 X”setGlobalNode，5 s 撤销吐司；
 *   · “订阅”小标题，右侧“今日 X ›”打开今日卡；订阅卡最多 3 行（名称、用量条、剩余、到期），§16.e④ 琥珀，
 *     其余“更多 N 个订阅”，点按去订阅页；
 *   · 自动切换提示（failover）：已连接时订阅 engine.sceneFailovers()，已切换 → “X 出口已自动切换到 Y”+ 撤销
 *     （吐司期间又换过节点则撤销不动作），AI 场景未切换 → 只提示。Mock 由设置页“模拟场景自动切换”触发。
 */
import { ActivitySheet } from './ActivitySheet';
import { CommandSheet } from './CommandSheet';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommandApplier } from '../app/CommandApplier';
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZSparkline } from '../components/ZSparkline';
import { Failover, GlobalPick, HomeSubs, HomeSubsView, SPARK_POINTS, SparkRing } from '../app/HomeModel';
import { SubscriptionWarning, SubscriptionsModel } from '../app/SubscriptionsModel';
import { ZTheme } from '../common/Theme';
import { ZColorsDark, ZColorsLight } from '../generated/ZTokens';
import { ZSegmented } from '../components/ZSegmented';
import { SceneRow } from './SceneRow';
import { SceneSheet } from './SceneSheet';
import { HapticKind, Haptics } from '../app/Haptics';
import {
  ConnectionState, ConnectionStatus, ErrorCode, ExitChange, NodeDetail, NodeId, NodeSummary, ProxyMode, ScanProgress, Scene,
  SceneFailoverNotice, ServiceHealth, Subscription, TrafficSample, UsageSummary
} from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { VpnState } from '../vpn/VpnController';
import { ZTerm } from '../generated/ZTerms';

/** 首页速率区组件 id（UiTest）。 */
export const HOME_TRAFFIC_ID: string = 'zephyr.home.traffic';
/** 资料库按钮（界面测试用）。 */
export const HOME_LIBRARY_ID: string = 'zephyr.home.library';
/** 全局模式卡“更换节点” / “更改为 X”（UiTest）。 */
export const HOME_GLOBAL_CHANGE_ID: string = 'zephyr.home.global.change';
export const HOME_GLOBAL_CONFIRM_ID: string = 'zephyr.home.global.confirm';
/** 首页订阅卡（UiTest）。 */
export const HOME_SUBS_ID: string = 'zephyr.home.subs';

const MODES: ProxyMode[] = [ProxyMode.RULE, ProxyMode.GLOBAL, ProxyMode.DIRECT];

@ComponentV2
export struct HomeView {
  @Event onOpenNodes: () => void = () => {};
  @Event onOpenLibrary: () => void = () => {};
  @Event onOpenSettings: () => void = () => {};
  /** 指令面板“查看全部” / 节点行：节点页，带查询。 */
  @Event onOpenNodesQuery: (query: string) => void = (query: string) => {};
  @Event onOpenRules: () => void = () => {};
  /** 流量卡“今日 X”：今日卡（M1-9，同 Android onToday）。 */
  @Event onOpenToday: () => void = () => {};
  /** 订阅卡：订阅页（同 Android onSubscriptions）。 */
  @Event onOpenSubscriptions: () => void = () => {};
  @Local showCommand: boolean = false;
  /** 最近连接 sheet（M1-8）。 */
  @Local showActivity: boolean = false;
  /** 资料库“场景”入口：每次递增 = 打开第一个场景的 sheet。 */
  @Param sceneRequest: number = 0;
  @Local showScene: boolean = false;
  @Local sheetSceneId: string = '';

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
  /** 最近 90 个下行样本（曲线）。 */
  @Local spark: number[] = [];
  @Local subList: Subscription[] = [];
  /** 分钟级时钟：到期 / “x 分钟前检测”。 */
  @Local minuteNow: number = Date.now();
  @Local scan: ScanProgress | undefined = undefined;
  /** 全局模式“更换节点”的内联建议（原型 gcf）。 */
  @Local globalProposal: NodeSummary | undefined = undefined;
  @Local globalChange: ExitChange | undefined = undefined;
  @Local globalLoading: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();

  private services: AppServices = AppServices.get();
  /** 指令面板最近一次关闭的时间（CommandApplier.suppressesTap）。 */
  private commandClosedAt: number = 0;
  private subs: StreamSub[] = [];
  private ticker: number = -1;
  private globalId: NodeId | undefined = undefined;
  private live: boolean = false;
  private ring: SparkRing = new SparkRing(SPARK_POINTS);
  private minuteTimer: number = -1;
  private failoverSub: StreamSub | undefined = undefined;
  /** 连接代次：断开后到达的 recentTraffic 回填作废。 */
  private liveGen: number = 0;

  aboutToAppear(): void {
    const engine = this.services.engine;
    this.subs.push(engine.connectionState().subscribe((c: ConnectionState) => this.onConnection(c)));
    this.subs.push(engine.traffic().subscribe((t: TrafficSample) => {
      this.upBps = t.upBps;
      this.downBps = t.downBps;
      if (this.status === ConnectionStatus.CONNECTED) {
        this.spark = this.ring.push(t.downBps);
      }
    }));
    this.subs.push(engine.scenes().subscribe((s: Scene[]) => {
      this.scenes = s;
    }));
    this.subs.push(engine.subscriptions().subscribe((s: Subscription[]) => {
      this.subList = s;
    }));
    this.subs.push(engine.scanProgress().subscribe((p: ScanProgress | undefined) => {
      this.scan = p;
    }));
    this.startMinuteClock();
    const vpn = this.services.vpn;
    if (vpn !== undefined) {
      this.subs.push(vpn.state().subscribe((v: VpnState) => {
        this.simulated = v.simulated;
      }));
    } else {
      // 预览器：没有 VPN 扩展，连接本来就是模拟的。
      this.simulated = true;
    }
    this.refreshUsage();
  }

  aboutToDisappear(): void {
    for (const s of this.subs) {
      s.cancel();
    }
    this.subs = [];
    this.stopTicker();
    this.stopFailovers();
    if (this.minuteTimer >= 0) {
      clearTimeout(this.minuteTimer);
      this.minuteTimer = -1;
    }
  }

  private refreshUsage(): void {
    this.services.engine.usageToday().then((u: UsageSummary) => {
      this.todayBytes = u.todayBytes;
    }).catch(() => {});
  }

  /** 分钟级时钟（同 Android HomeViewModel：对齐整分，顺带刷新今日用量）。 */
  private startMinuteClock(): void {
    const wait = 60000 - Date.now() % 60000;
    this.minuteTimer = setTimeout(() => {
      this.minuteNow = Date.now();
      this.refreshUsage();
      this.startMinuteClock();
    }, wait);
  }

  // ── 自动切换提示（U8）────────────────────────────────────────────────────
  private startFailovers(): void {
    if (this.failoverSub !== undefined) {
      return;
    }
    this.failoverSub = this.services.engine.sceneFailovers().subscribe((n: SceneFailoverNotice) => this.onFailover(n));
  }

  private stopFailovers(): void {
    if (this.failoverSub !== undefined) {
      this.failoverSub.cancel();
      this.failoverSub = undefined;
    }
  }

  private onFailover(n: SceneFailoverNotice): void {
    if (this.status !== ConnectionStatus.CONNECTED) {
      return;
    }
    const name = this.resolve(Labels.sceneNameRaw(n.sceneName));
    hilog.info(0x5A50, 'HomeView', 'failover %{public}s switched=%{public}s', n.sceneId, String(n.switchedTo !== undefined));
    const to = n.switchedTo;
    if (to === undefined) {
      this.services.toasts.show(this.text($r('app.string.home_failover_none'), name));
      return;
    }
    const engine = this.services.engine;
    const prev = n.previousNodeId;
    if (prev === undefined) {
      this.services.toasts.show(this.text2($r('app.string.home_failover_switched'), name, to));
      return;
    }
    this.services.toasts.show(this.text2($r('app.string.home_failover_switched'), name, to), {
      onUndo: () => {
        // 吐司期间用户又换了节点：撤销不覆盖那次选择（同 iOS）。
        if (Failover.canUndo(n, this.scenes)) {
          engine.applySceneChange(n.sceneId, prev).catch(() => {});
        }
      }
    });
  }

  // ── 全局模式卡（U6）──────────────────────────────────────────────────────
  private toggleGlobalChange(): void {
    if (this.globalProposal !== undefined) {
      this.globalProposal = undefined;
      this.globalChange = undefined;
      return;
    }
    if (this.globalLoading) {
      return;
    }
    this.globalLoading = true;
    const engine = this.services.engine;
    const cur = this.globalNode;
    GlobalPick.candidates(engine, this.scenes).then((nodes: NodeSummary[]) => {
      const best = GlobalPick.best(nodes, cur);
      if (best === undefined) {
        this.services.toasts.show(this.text($r('app.string.home_error_node_gone'),
          this.resolve($r('app.string.home_action_load_nodes'))));
        return;
      }
      engine.previewGlobalChange(best.id).then((x: ExitChange) => {
        this.globalChange = x;
      }).catch(() => {
        this.globalChange = undefined;
      }).finally(() => {
        if (this.mode === ProxyMode.GLOBAL) {
          this.globalProposal = best;
        }
      });
    }).catch(() => {}).finally(() => {
      this.globalLoading = false;
    });
  }

  private confirmGlobal(): void {
    const to = this.globalProposal;
    if (to === undefined || this.applying) {
      return;
    }
    const from = this.globalNode;
    const engine = this.services.engine;
    this.applying = true;
    engine.setGlobalNode(to.id).then(() => {
      Haptics.play(HapticKind.SUCCESS);
      this.globalProposal = undefined;
      this.globalChange = undefined;
      this.services.toasts.show(this.text($r('app.string.home_switched_to'), to.name), from === undefined ? undefined : {
        onUndo: () => {
          engine.setGlobalNode(from.id).catch(() => {});
        }
      });
    }).catch(() => {
      this.services.toasts.show(this.text($r('app.string.home_error_failed'),
        this.resolve($r('app.string.home_action_switch_node'))));
    }).finally(() => {
      this.applying = false;
    });
  }

  @Monitor('sceneRequest')
  onSceneRequest(): void {
    if (this.sceneRequest > 0 && this.scenes.length > 0) {
      this.openScene(this.scenes[0]);
    }
  }

  private openScene(s: Scene): void {
    if (CommandApplier.suppressesTap(this.commandClosedAt, Date.now())) {
      // 指令面板刚关：这一下多半是落空到首页的“幽灵点按”（真机：再点“应用”打开了 AI 场景 sheet）。
      hilog.info(0x5A50, 'HomeView', 'scene tap ignored right after command sheet closed: %{public}s', s.id);
      return;
    }
    hilog.info(0x5A50, 'HomeView', 'open scene sheet %{public}s (was showing=%{public}s)', s.id, String(this.showScene));
    this.sheetSceneId = s.id;
    if (this.showScene) {
      // 能点到场景行说明 sheet 实际已不在（有 sheet 时遮罩挡住首页），showScene 是残留的 true：
      // 再赋 true 不会触发 bindSheet，表现为“点了没反应”。先复位，下一帧再打开。
      this.showScene = false;
      setTimeout(() => {
        this.showScene = true;
      }, 32);
      return;
    }
    this.showScene = true;
  }

  private closeCommand(): void {
    this.showCommand = false;
    this.commandClosedAt = Date.now();
  }

  private onConnection(c: ConnectionState): void {
    this.status = c.status;
    this.mode = c.mode;
    this.since = c.since ?? 0;
    this.errorCode = c.status === ConnectionStatus.FAILED && c.error !== undefined ? c.error.code : undefined;
    if (c.status === ConnectionStatus.CONNECTED) {
      this.startTicker();
      this.startFailovers();
      if (!this.live) {
        this.live = true;
        this.backfillSpark();
      }
    } else {
      this.stopTicker();
      this.stopFailovers();
      this.upBps = 0;
      this.downBps = 0;
      this.live = false;
      this.liveGen++;
      this.ring.clear();
      this.spark = [];
    }
    if (c.mode !== ProxyMode.GLOBAL) {
      this.globalProposal = undefined;
      this.globalChange = undefined;
    }
    if (c.globalNodeId !== this.globalId) {
      this.globalId = c.globalNodeId;
      this.loadGlobal(c.globalNodeId);
    }
  }

  /** 刚连上：recentTraffic(90) 回填曲线（同 Android trafficLive）。 */
  private backfillSpark(): void {
    const gen = ++this.liveGen;
    this.services.engine.recentTraffic(SPARK_POINTS).then((back: TrafficSample[]) => {
      if (gen === this.liveGen && back.length > 0) {
        this.spark = this.ring.fill(back);
      }
    }).catch(() => {});
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

  private plain(r: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id) : '';
    } catch (e) {
      return '';
    }
  }

  private text(r: Resource, arg: string): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, arg) : arg;
    } catch (e) {
      return arg;
    }
  }

  private text2(r: Resource, a: string, b: string): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, a, b) : a + ' ' + b;
    } catch (e) {
      return a + ' ' + b;
    }
  }

  private resolve(r: ResourceStr): string {
    if (typeof r === 'string') {
      return r;
    }
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync((r as Resource).id) : '';
    } catch (e) {
      return '';
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
        // 已连接时速率区打开“最近连接”（M1-8，同 Android 风区 onActivity / H-P2-3）。
        Row({ space: 12 }) {
          this.rateTile($r('app.string.hm_home_download'), this.downBps, $r('app.color.color_download'))
          this.rateTile($r('app.string.hm_home_upload'), this.upBps, $r('app.color.screen_up'))
        }
        .width('100%')
        .id(HOME_TRAFFIC_ID)
        .accessibilityGroup(this.status === ConnectionStatus.CONNECTED)
        .accessibilityRole(this.status === ConnectionStatus.CONNECTED ? AccessibilityRoleType.BUTTON :
          AccessibilityRoleType.TEXT)
        .accessibilityDescription(this.status === ConnectionStatus.CONNECTED ? this.text($r('app.string.activity_title'), '') : '')
        .onClick(() => {
          if (this.status === ConnectionStatus.CONNECTED) {
            hilog.info(0x5A50, 'HomeView', 'open recent connections');
            this.showActivity = true;
          }
        })
        .bindSheet(this.showActivity, this.activitySheet(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: true,
          dragBar: true,
          backgroundColor: $r('app.color.screen_bg'),
          onDisappear: () => {
            this.showActivity = false;
          }
        })

        // 曲线（U4）：已连接 = 最近 90 秒下行；未连接 = 虚线基线。点曲线同样打开最近连接（原型整块 .wind）。
        ZSparkline({
          values: this.spark,
          color: this.theme.isDark ? ZColorsDark.colorDownload : ZColorsLight.colorDownload,
          idle: !this.isConnected(),
          dark: this.theme.isDark,
          description: this.plain($r('app.string.home_spark_a11y'))
        })
          .width('100%')
          .height(72)
          .onClick(() => {
            if (this.status === ConnectionStatus.CONNECTED) {
              this.showActivity = true;
            }
          })
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

  /** 小标题（同 Android ZSectionHeader）：左标题，右侧可选说明（可点）。 */
  @Builder
  sectionHeader(title: ResourceStr, trailing: string, onTrailing: (() => void) | undefined) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t3'))
        .accessibilityRole(AccessibilityRoleType.TEXT)
      Blank()
      if (trailing.length > 0) {
        Row({ space: 2 }) {
          Text(trailing)
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          if (onTrailing !== undefined) {
            Text('›')
              .fontSize(15)
              .fontColor($r('app.color.screen_t4'))
              .accessibilityLevel('no')
          }
        }
        .accessibilityGroup(true)
        .accessibilityRole(onTrailing !== undefined ? AccessibilityRoleType.BUTTON : AccessibilityRoleType.TEXT)
        .onClick(() => {
          if (onTrailing !== undefined) {
            onTrailing();
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
    .margin({ top: 8 })
  }

  /** “场景”右侧：扫描进度 / 检测中 / “x 分钟前检测”；全局模式不显示（同 Android）。 */
  private scenesTrailing(): string {
    if (this.mode === ProxyMode.GLOBAL) {
      return '';
    }
    const p = this.scan;
    if (p !== undefined) {
      return this.textNum2($r('app.string.home_scan_progress'), p.done, p.total);
    }
    let tested = 0;
    for (const s of this.scenes) {
      tested = Math.max(tested, s.testedAt ?? 0);
    }
    if (tested <= 0) {
      return '';
    }
    const ago = Format.ago(tested, this.minuteNow);
    return this.text($r('app.string.home_scenes_tested'), this.textNum(Labels.ago(ago), ago.count));
  }

  private textNum(r: Resource, n: number): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, n) : String(n);
    } catch (e) {
      return String(n);
    }
  }

  private textNum2(r: Resource, a: number, b: number): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, a, b) : String(a) + '/' + String(b);
    } catch (e) {
      return String(a) + '/' + String(b);
    }
  }

  private todayTrailing(): string {
    return this.todayBytes >= 0 ? this.text($r('app.string.home_today_usage'), Format.bytesText(this.todayBytes)) : '';
  }

  /** 原型 global（689–692）：全局模式卡 + “更换节点”内联建议。 */
  @Builder
  globalCard() {
    Column({ space: 5 }) {
      Text(ZTerm.modeGlobalTitle)
        .fontSize(15)
        .fontColor($r('app.color.screen_t1'))
      Text(this.globalNode !== undefined ? $r('app.string.home_global_body', this.globalNode.name)
        : $r('app.string.home_global_body_any'))
        .fontSize(13)
        .lineHeight(19.5)
        .fontColor($r('app.color.screen_t3'))
      Row({ space: 8 }) {
        Button($r('app.string.home_global_use_rule'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_on_primary'))
          .backgroundColor($r('app.color.screen_primary'))
          .onClick(() => this.setMode(MODES.indexOf(ProxyMode.RULE)))
        Button($r('app.string.home_global_change_node'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
          .backgroundColor($r('app.color.screen_hl'))
          .enabled(!this.globalLoading)
          .id(HOME_GLOBAL_CHANGE_ID)
          .onClick(() => this.toggleGlobalChange())
      }
      .width('100%')
      .margin({ top: 9 })
      if (this.globalProposal !== undefined) {
        this.globalConfirm(this.globalProposal)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(22)
    .backgroundColor($r('app.color.screen_s1'))
    .alignItems(HorizontalAlign.Start)
  }

  private globalFrom(): string {
    const c = this.globalChange;
    if (c !== undefined && c.fromIp !== undefined) {
      return c.fromRegion + ' ' + c.fromIp;
    }
    const n = this.globalNode;
    return n !== undefined ? n.region + ' ' + n.name : this.resolve($r('app.string.common_current'));
  }

  private globalTo(p: NodeSummary): string {
    const c = this.globalChange;
    return c !== undefined && c.toIp !== undefined ? c.toRegion + ' ' + c.toIp : p.region + ' ' + p.name;
  }

  @Builder
  globalConfirm(p: NodeSummary) {
    Column({ space: 8 }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Circle({ width: 6, height: 6 }).fill($r('app.color.screen_amber'))
          Text($r('app.string.common_exit_ip_changes'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t1'))
        }
        Text(this.globalFrom() + ' → ' + this.globalTo(p))
          .fontSize(12.5)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t2'))
          .maxLines(2)
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.screen_s3'))
      .alignItems(HorizontalAlign.Start)
      Text($r('app.string.home_global_change_note', p.name))
        .fontSize(13)
        .fontColor($r('app.color.screen_t3'))
      Row({ space: 8 }) {
        Button($r('app.string.home_global_change_to', p.name))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_on_primary'))
          .backgroundColor($r('app.color.screen_primary'))
          .enabled(!this.applying)
          .id(HOME_GLOBAL_CONFIRM_ID)
          .onClick(() => this.confirmGlobal())
        Button($r('app.string.common_cancel'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
          .backgroundColor($r('app.color.screen_hl'))
          .onClick(() => this.toggleGlobalChange())
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .margin({ top: 9 })
    .alignItems(HorizontalAlign.Start)
  }

  private expiryLine(at: number): string {
    const ex = Format.expiry(at, this.minuteNow);
    return this.textNum(Labels.expiry(ex), ex.days);
  }

  /** 订阅摘要（同 Android SubscriptionsCard）：名称、用量条、剩余、到期；§16.e④ 琥珀。 */
  @Builder
  subRow(s: Subscription, divider: boolean) {
    Column() {
      Row({ space: 24 }) {
        Column({ space: 12 }) {
          Text(s.name)
            .fontSize(17)
            .fontColor($r('app.color.screen_t1'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Progress({ value: SubscriptionsModel.usedFraction(s) * 100, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(SubscriptionWarning.isWarning(s, this.minuteNow) ? $r('app.color.screen_amber') : $r('app.color.screen_t3'))
            .backgroundColor($r('app.color.screen_s3'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          if (s.remainingBytes !== undefined) {
            Text(Format.bytesText(s.remainingBytes))
              .fontSize(15)
              .fontFamily('monospace')
              .fontColor($r('app.color.screen_t1'))
          }
          if (s.expiresAt !== undefined) {
            Text(this.expiryLine(s.expiresAt))
              .fontSize(12)
              .fontColor(SubscriptionWarning.isWarning(s, this.minuteNow) ? $r('app.color.screen_amber') : $r('app.color.screen_t3'))
          }
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding(18)
      if (divider) {
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl'))
      }
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .onClick(() => this.onOpenSubscriptions())
  }

  @Builder
  subsCard(v: HomeSubsView) {
    Column() {
      ForEach(v.rows, (s: Subscription, i: number) => {
        this.subRow(s, i < v.rows.length - 1 || v.more > 0)
      }, (s: Subscription) => s.id + ':' + String(s.usedBytes) + ':' + String(s.remainingBytes) + ':' + String(s.expiresAt) +
        ':' + String(this.minuteNow))
      if (v.more > 0) {
        Row() {
          Text($r('app.plural.home_subs_more', v.more, v.more))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 14, bottom: 14 })
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => this.onOpenSubscriptions())
      }
    }
    .width('100%')
    .borderRadius(22)
    .backgroundColor($r('app.color.screen_s1'))
    .clip(true)
    .id(HOME_SUBS_ID)
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
          onOpen: () => this.openScene(s),
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

  @Builder
  commandSheet() {
    CommandSheet({
      onOpenNodes: (q: string) => {
        this.showCommand = false;
        this.onOpenNodesQuery(q);
      },
      onOpenRules: () => {
        this.showCommand = false;
        this.onOpenRules();
      },
      onDone: () => {
        this.closeCommand();
      }
    })
  }

  /** 底栏（原型 .dock）：左侧指令栏 + 右侧资料库按钮。 */
  @Builder
  dock() {
    Column() {
      Row({ space: 10 }) {
        // 指令栏（原型 .cmd）：整条可点，打开指令面板；读屏读作按钮“搜索或输入指令”。
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.screen_t3')])
          Text($r('app.string.command_placeholder'))
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .height(52)
        .padding({ left: 16, right: 16 })
        .borderRadius(26)
        .backgroundColor($r('app.color.screen_cmd_bg'))
        .shadow({ radius: 12, color: '#22000000', offsetY: 4 })
        .accessibilityGroup(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilityText($r('app.string.command_placeholder'))
        .onClick(() => {
          this.showCommand = true;
        })
        .bindSheet(this.showCommand, this.commandSheet(), {
          detents: [SheetSize.LARGE, SheetSize.MEDIUM],
          showClose: true,
          dragBar: true,
          backgroundColor: $r('app.color.screen_bg'),
          onDisappear: () => {
            this.closeCommand();
          }
        })
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
        .id(HOME_LIBRARY_ID)
        .onClick(() => this.onOpenLibrary())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  activitySheet() {
    ActivitySheet()
  }

  @Builder
  sceneSheet() {
    SceneSheet({
      sceneId: this.sheetSceneId,
      onPick: (s: Scene, n: NodeSummary) => {
        this.showScene = false;
        this.pick(s, n);
      },
      onClose: () => {
        this.showScene = false;
      }
    })
  }

  private sceneTitle(): ResourceStr {
    const s = this.scenes.find((x: Scene) => x.id === this.sheetSceneId);
    return s !== undefined ? Labels.sceneName(s) : '';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.content()
      this.dock()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.screen_bg'))
    .bindSheet(this.showScene, this.sceneSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      title: { title: this.sceneTitle() },
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.screen_bg'),
      onDisappear: () => {
        this.showScene = false;
      }
    })
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

        // 场景（同 Android item scenes-h / scenes）：全局模式换成全局模式卡。
        this.sectionHeader(ZTerm.scenes, this.scenesTrailing(), undefined)
        if (this.mode === ProxyMode.GLOBAL) {
          this.globalCard()
        } else if (this.scenes.length > 0) {
          this.sceneRows()
        } else {
          this.currentNode()
        }

        // 订阅（U7）：右侧“今日 X ›”打开今日卡。
        this.sectionHeader(ZTerm.subscriptions, this.todayTrailing(), this.todayBytes >= 0 ? () => this.onOpenToday() : undefined)
        if (this.subList.length > 0) {
          this.subsCard(HomeSubs.view(this.subList))
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
