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
import { ZSheetHeader } from '../components/ZSheetHeader';
import { ZBtn } from '../common/ZButtonMods';
import { ActivitySheet } from './ActivitySheet';
import { CommandSheet } from './CommandSheet';
import { CommandPage } from '../app/CommandResults';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommandApplier } from '../app/CommandApplier';
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZSparkline } from '../components/ZSparkline';
import { Failover, GlobalPick, HomeSubs, HomeSubsView, SPARK_POINTS, SparkRing } from '../app/HomeModel';
import { JUDGEMENT_MAX_AGE_MS, JUDGEMENT_THRESHOLD_MS } from '../app/NodeListModel';
import { SubscriptionWarning, SubscriptionsModel } from '../app/SubscriptionsModel';
import { ZTheme } from '../common/Theme';
import { ZColorsDark, ZColorsLight } from '../generated/ZTokens';
import { ZHero } from '../common/ZTypeMods';
import { SceneRow } from './SceneRow';
import { SceneSheet } from './SceneSheet';
import { HapticKind, Haptics } from '../app/Haptics';
import {
  ConnectionState, ConnectionStatus, ErrorCode, ExitChange, NodeDetail, NodeFunnel, NodeId, NodeSummary, ProxyMode, ScanProgress, Scene,
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
  /** 指令面板设置组的页面（J-3）。 */
  @Event onOpenPage: (p: CommandPage) => void = (p: CommandPage) => {};
  @Local showCommand: boolean = false;
  /** 最近连接 sheet（M1-8）。 */
  @Local showActivity: boolean = false;
  /** 资料库“场景”入口：每次递增 = 打开第一个场景的 sheet。 */
  @Param sceneRequest: number = 0;
  @Local showScene: boolean = false;
  /** 指令面板「打开场景」：面板消失后再开场景 sheet。 */
  private sceneAfterCommand: Scene | undefined = undefined;
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
  /** §19.a 每个场景自己的漏斗（J-1 迷你漏斗）；取不到的场景不在表里。 */
  @Local funnels: Map<string, NodeFunnel> = new Map<string, NodeFunnel>();
  private funnelTimer: number = -1;
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
      this.scheduleFunnels();
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
    if (this.funnelTimer >= 0) {
      clearTimeout(this.funnelTimer);
      this.funnelTimer = -1;
    }
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

  /** 场景刷新后 500 ms 内合并，每个场景各取一次 sceneFunnel（契约 §19.a 性能说明：与 scenes() 刷新同节流）。 */
  private scheduleFunnels(): void {
    if (this.funnelTimer >= 0) {
      return;
    }
    this.funnelTimer = setTimeout(() => {
      this.funnelTimer = -1;
      this.refreshFunnels();
    }, 500);
  }

  private refreshFunnels(): void {
    const engine = this.services.engine;
    const ids = this.scenes.map((s: Scene) => s.id);
    Promise.all(ids.map((id: string) => engine.sceneFunnel(id, JUDGEMENT_MAX_AGE_MS, JUDGEMENT_THRESHOLD_MS)
      .catch((): NodeFunnel | undefined => undefined)))
      .then((fs: (NodeFunnel | undefined)[]) => {
        const m = new Map<string, NodeFunnel>();
        fs.forEach((f: NodeFunnel | undefined, i: number) => {
          if (f !== undefined) {
            m.set(ids[i], f);
          }
        });
        this.funnels = m;
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

  @Local showModeMenu: boolean = false;

  private isOn(): boolean {
    return this.status === ConnectionStatus.CONNECTED || this.status === ConnectionStatus.CONNECTING;
  }

  /** 状态行下的说明（同 Android HomeStatus）：失败 → 下一步提示；已连接 → 时长；否则场景数。 */
  private subLine(): ResourceStr {
    if (this.status === ConnectionStatus.FAILED && this.errorCode !== undefined) {
      return Labels.connectError(this.errorCode);
    }
    if (this.isConnected() && this.since > 0) {
      return Format.duration(this.now - this.since);
    }
    return $r('app.plural.home_scene_count', this.scenes.length, this.scenes.length);
  }

  /** “已连接” + 大开关；下面“规则 ⌄  2:14:07”（原型 01/02，Android HomeStatus）。 */
  @Builder
  header() {
    Column() {
      Row({ space: 12 }) {
        Text(Labels.status(this.status))
          .attributeModifier(ZHero.status())
          .fontColor($r('app.color.screen_t1'))
          .layoutWeight(1)
          .accessibilityRole(AccessibilityRoleType.TEXT)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        Toggle({ type: ToggleType.Switch, isOn: this.isOn() })
          .width(64)
          .height(38)
          .selectedColor($r('app.color.screen_green'))
          .switchPointColor(Color.White)
          .enabled(!this.isTransitioning() && !this.busy)
          .accessibilityText($r('app.string.common_connect'))
          .onChange((on: boolean) => {
            if (on !== this.isOn()) {
              Haptics.play(HapticKind.SELECTION);
              this.toggle();
            }
          })
      }
      .width('100%')

      Row({ space: 18 }) {
        Row({ space: 4 }) {
          Text(Labels.mode(this.mode))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.screen_t1'))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([$r('app.color.screen_t2')])
            .rotate({ angle: this.showModeMenu ? 180 : 0 })
            .animation({ duration: 200, curve: Curve.EaseOut })
        }
        .padding({ top: 6, bottom: 6 })
        .accessibilityGroup(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilityDescription(ZTerm.switchMode)
        .stateStyles({ pressed: { .opacity(0.5) }, normal: { .opacity(1) } })
        .onClick(() => {
          this.showModeMenu = true;
        })
        .bindMenu(this.showModeMenu, this.modeMenu(), {
          placement: Placement.BottomLeft,
          onDisappear: () => {
            this.showModeMenu = false;
          }
        })
        Text(this.subLine())
          .attributeModifier(ZHero.numeric(14))
          .fontColor(this.status === ConnectionStatus.FAILED ? $r('app.color.screen_red_text') : $r('app.color.screen_t3'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.simulated && this.isConnected()) {
        Text($r('app.string.hm_home_simulated'))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 6, right: 6 })
  }

  /** 模式下拉（Android ModePicker）：模式名 + 说明，当前项打勾。 */
  @Builder
  modeMenu() {
    Column() {
      ForEach(MODES, (m: ProxyMode, i: number) => {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(Labels.mode(m))
              .fontSize(16)
              .fontColor($r('app.color.screen_t1'))
            Text(Labels.modeHint(m))
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (m === this.mode) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([this.theme.accentColor()])
          }
        }
        .width(200)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .stateStyles({ pressed: { .backgroundColor($r('app.color.screen_s3')) }, normal: { .backgroundColor(Color.Transparent) } })
        .onClick(() => {
          this.showModeMenu = false;
          if (m !== this.mode) {
            Haptics.play(HapticKind.SELECTION);
            this.setMode(i);
          }
        })
      }, (m: ProxyMode) => m as string)
    }
    .padding({ top: 6, bottom: 6 })
  }

  /** 速率（Android ZTrafficStat）：下行大数字 + 单位 + ↓，下一行上行小字 + ↑。 */
  @Builder
  trafficStat() {
    Column({ space: 2 }) {
      Row() {
        Text(Format.rate(this.downBps).value)
          .attributeModifier(ZHero.hero())
          .fontColor($r('app.color.screen_t1'))
        Text(Format.rate(this.downBps).unit + '/s')
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
          .margin({ left: 10, bottom: 8 })
        SymbolGlyph($r('sys.symbol.arrow_down'))
          .fontSize(16)
          .fontColor([$r('app.color.color_download')])
          .margin({ left: 4, bottom: 9 })
      }
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 4 }) {
        Text(Format.rate(this.upBps).value + ' ' + Format.rate(this.upBps).unit + '/s')
          .attributeModifier(ZHero.numeric(13))
          .fontColor($r('app.color.screen_t2'))
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(14)
          .fontColor([$r('app.color.screen_up')])
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 6, right: 6 })
    .direction(Direction.Ltr)
  }

  /**
   * 风区（原型 .wind）：已连接 = 速率 + 曲线（整块点按打开“最近连接”，H-P2-3）；未连接 = 150 高的虚线基线。
   * 曲线左右出血到屏幕边缘（同 Android / 原型）。
   */
  @Builder
  traffic() {
    if (this.isConnected()) {
      Column() {
        this.trafficStat()
        ZSparkline({
          values: this.spark,
          color: this.theme.isDark ? ZColorsDark.colorDownload : ZColorsLight.colorDownload,
          idle: false,
          dark: this.theme.isDark,
          description: this.plain($r('app.string.home_spark_a11y'))
        })
          .width('calc(100% + 32vp)')
          .height(72)
          .margin({ left: -16 })
      }
      .width('100%')
      .margin({ top: 36 })
      .alignItems(HorizontalAlign.Start)
      .id(HOME_TRAFFIC_ID)
      .accessibilityGroup(true)
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .accessibilityText(this.plain($r('app.string.activity_title')))
      .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
      .onClick(() => {
        hilog.info(0x5A50, 'HomeView', 'open recent connections');
        this.showActivity = true;
      })
      .bindSheet(this.showActivity, this.activitySheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        dragBar: true,
        backgroundColor: $r('app.color.screen_s1'),
        onDisappear: () => {
          this.showActivity = false;
        }
      })
    } else {
      ZSparkline({
        values: [],
        color: this.theme.isDark ? ZColorsDark.colorDownload : ZColorsLight.colorDownload,
        idle: true,
        dark: this.theme.isDark,
        description: ''
      })
        .width('calc(100% + 32vp)')
        .height(150)
        .margin({ left: -16 })
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
              .fontColor($r('app.color.screen_t3'))
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
          .attributeModifier(ZBtn.primary())
          .layoutWeight(1)
          .onClick(() => this.setMode(MODES.indexOf(ProxyMode.RULE)))
        Button($r('app.string.home_global_change_node'))
          .attributeModifier(ZBtn.secondary())
          .layoutWeight(1)
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
          .attributeModifier(ZBtn.primary())
          .layoutWeight(1)
          .enabled(!this.applying)
          .id(HOME_GLOBAL_CONFIRM_ID)
          .onClick(() => this.confirmGlobal())
        Button($r('app.string.common_cancel'))
          .attributeModifier(ZBtn.secondary())
          .layoutWeight(1)
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
        Divider().strokeWidth(1).color($r('app.color.screen_hl'))
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
          .attributeModifier(ZBtn.primary())
          .layoutWeight(1)
          .enabled(!this.applying)
          .onClick(() => this.confirmPending())
        Button($r('app.string.common_cancel'))
          .attributeModifier(ZBtn.secondary())
          .layoutWeight(1)
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
          funnel: this.funnels.get(s.id),
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
    .borderRadius(24)
    .backgroundColor($r('app.color.screen_s2'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
    .clip(true)
  }

  /** 顶栏（原型 .top，Android HomeTopBar）：状态点（已连接带光晕）+ 品牌字标 + 设置。 */
  @Builder
  topBar() {
    Row() {
      Stack() {
        if (this.isConnected()) {
          Circle({ width: 16, height: 16 }).fill($r('app.color.screen_green')).fillOpacity(0.22)
        }
        Circle({ width: 8, height: 8 }).fill(this.isConnected() ? $r('app.color.screen_green') : $r('app.color.screen_t4'))
      }
      .width(16)
      .height(16)
      .accessibilityLevel('no')
      Row({ space: 4 }) {
        Image($r('app.media.ic_zephyr_glyph'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.screen_t1'))
        Text('Zephyr')
          .fontSize(15)
          .fontWeight(600)
          .letterSpacing(-0.1)
          .fontColor($r('app.color.screen_t1'))
      }
      .margin({ left: 6 })
      .direction(Direction.Ltr)
      .accessibilityGroup(true)
      .accessibilityText('Zephyr')
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
    .padding({ left: 6 })
    .margin({ right: -8 })
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
      },
      connected: this.status === ConnectionStatus.CONNECTED || this.status === ConnectionStatus.CONNECTING,
      scenes: this.scenes,
      onSetMode: (m: ProxyMode) => {
        this.closeCommand();
        this.setMode(MODES.indexOf(m));
      },
      onToggle: (connect: boolean) => {
        this.closeCommand();
        const on = this.status === ConnectionStatus.CONNECTED || this.status === ConnectionStatus.CONNECTING;
        if (on !== connect) {
          this.toggle();
        }
      },
      onOpenScene: (id: string) => {
        this.showCommand = false;
        const sc = this.scenes.find((x: Scene) => x.id === id);
        if (sc !== undefined) {
          // 两个 sheet 不叠：等指令面板消失（onDisappear）再开场景 sheet。
          this.sceneAfterCommand = sc;
        }
      },
      onOpenPage: (pg: CommandPage) => {
        this.showCommand = false;
        this.onOpenPage(pg);
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
          // §9.7：玻璃上的文字用 t2，不用 t3（玻璃合成到最亮底时余量最小）。
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.screen_t2')])
          Text($r('app.string.command_placeholder'))
            .fontSize(15)
            .fontColor($r('app.color.screen_t2'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .height(52)
        .padding({ left: 16, right: 16 })
        .borderRadius(26)
        .glassBar()
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
            const sc = this.sceneAfterCommand;
            if (sc !== undefined) {
              this.sceneAfterCommand = undefined;
              this.openScene(sc);
            }
          }
        })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(22)
            .fontColor([$r('app.color.screen_t2')])
        }
        .width(52)
        .height(52)
        .glassButton()
        .accessibilityText($r('app.string.common_library'))
        .id(HOME_LIBRARY_ID)
        .onClick(() => this.onOpenLibrary())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    // §9.7：滚动内容在底栏背后用 screen.fade 渐隐盖住，下方不露出可滚动内容。
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[$r('app.color.screen_fade_clear'), 0], [$r('app.color.screen_fade'), 0.55]]
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  activitySheet() {
    ActivitySheet({
      onDone: () => {
        this.showActivity = false;
      }
    })
  }

  @Builder
  sceneSheet() {
    Column() {
      ZSheetHeader({
        title: this.sceneTitle(),
        onDone: () => {
          this.showScene = false;
        }
      })
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
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
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
      showClose: false,
      dragBar: true,
      backgroundColor: $r('app.color.screen_s1'),
      onDisappear: () => {
        this.showScene = false;
      }
    })
  }

  @Builder
  content() {
    Scroll() {
      Column() {
        // 间距同 Android HomeContent：顶栏 12 → 状态 24 → 风区 36 → 场景 28 → 订阅 28。
        this.topBar()
        Blank().height(24)
        this.header()
        this.traffic()

        // 场景（同 Android item scenes-h / scenes）：全局模式换成全局模式卡。
        Blank().height(28)
        this.sectionHeader(ZTerm.scenes, this.scenesTrailing(), undefined)
        Blank().height(8)
        if (this.mode === ProxyMode.GLOBAL) {
          this.globalCard()
        } else if (this.scenes.length > 0) {
          this.sceneRows()
        } else {
          this.currentNode()
        }

        // 订阅（U7）：右侧“今日 X ›”打开今日卡。
        Blank().height(28)
        this.sectionHeader(ZTerm.subscriptions, this.todayTrailing(), this.todayBytes >= 0 ? () => this.onOpenToday() : undefined)
        Blank().height(8)
        if (this.subList.length > 0) {
          this.subsCard(HomeSubs.view(this.subList))
        }
      }
      .width('100%')
      // 底部留出底栏（52 + 20）+ 间距，最后一张卡不被资料库按钮挡住。
      .padding({ left: 16, right: 16, top: 12, bottom: 120 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}

/**
 * §9.7 悬浮玻璃（设计评审 J-4）：只用于首页指令栏和资料库按钮，其余卡片保持实色。
 * 鸿蒙不适用 Liquid Glass（平台差异）：screen.glass + COMPONENT_ULTRA_THIN 模糊 + 细描边。
 */
@Extend(Row)
function glassBar() {
  .backgroundColor($r('app.color.screen_glass'))
  .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
  .border({ width: 0.5, color: $r('app.color.screen_hl') })
  .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
}

@Extend(Button)
function glassButton() {
  .backgroundColor($r('app.color.screen_glass'))
  .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
  .border({ width: 0.5, color: $r('app.color.screen_hl') })
  .shadow({ radius: 12, color: '#1F000000', offsetY: 4 })
}
