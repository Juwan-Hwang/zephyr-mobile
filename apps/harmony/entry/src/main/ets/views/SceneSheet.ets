import { LengthMetrics } from '@kit.ArkUI';
/*
 * 场景详情 sheet（M1-5 / U9，原型 sceneSheet 804–823；对照 Android ui/scene/SceneSheet.kt、iOS Scene/SceneSheet）。
 * 首页场景行点按、资料库“场景”入口打开（bindSheet，由 HomeView 承载）。内容全部来自引擎：
 * - 可用数 + 导语“检测自 N 个订阅中的 M 个节点”（SceneSheetModel.lede）；
 * - 来源分段：订阅分组 / Zephyr 优选（setSceneSource）；Zephyr 优选时显示漏斗（§15.c nodeFunnel，300 ms）；
 * - 候选（按延迟，最快 12 个）：当前节点标“当前”不可点，其余点按 → 收起 sheet，首页出“更改出口 IP？”确认卡；
 *   钉了例外的节点标“X 固定”；
 * - 设置：节点不可用时（AI 询问 / 其余自动切换）、节点范围仅 4K（§15.h，由指令“视频只用 4K 节点”设置）、
 *   各例外、检测频率（结果保留，24 h = 每天，仅 Wi‑Fi）、重新检测（retestScene，进行中显示“检测中…”）；
 * - 脚注：优选只存在 Zephyr 里 + 上次检测时间。
 * 只读行没有箭头、不响应点按。
 */
import { ZHero } from '../common/ZTypeMods';
import { LatencyTickBar } from '../components/LatencyTickBar';
import { AppServices } from '../app/AppServices';
import { HapticKind, Haptics } from '../app/Haptics';
import { Lede, LedeKind, SceneSheetModel } from '../app/SceneSheetModel';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { ZSegmented } from '../components/ZSegmented';
import {
  NodeFunnel, NodeSummary, Scene, SceneException, SceneSource, Settings, Subscription
} from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';
import { SceneFunnel } from './SceneFunnel';

@ComponentV2
export struct SceneSheet {
  @Param @Require sceneId: string;
  /** 点了非当前候选：由首页出确认卡（同 Android onPick：先收起 sheet）。 */
  @Event onPick: (scene: Scene, node: NodeSummary) => void = (scene: Scene, node: NodeSummary) => {};
  @Event onClose: () => void = () => {};

  @Local scene: Scene | undefined = undefined;
  @Local candidates: NodeSummary[] = [];
  @Local funnel: NodeFunnel | undefined = undefined;
  @Local subs: number = 0;
  @Local settings: Settings | undefined = undefined;
  @Local retesting: boolean = false;
  @Local now: number = Date.now();
  @Local theme: ZTheme = ZTheme.shared();

  private streams: StreamSub[] = [];
  private candidatesKey: string = '';
  private funnelKey: string = '';

  aboutToAppear(): void {
    const e = AppServices.get().engine;
    this.streams.push(e.scenes().subscribe((list: Scene[]) => {
      const s = list.find((x: Scene) => x.id === this.sceneId);
      if (s !== undefined) {
        this.scene = s;
        this.reload(s);
      }
    }));
    this.streams.push(e.settings().subscribe((s: Settings) => {
      this.settings = s;
    }));
    this.streams.push(e.subscriptions().subscribe((l: Subscription[]) => {
      this.subs = l.length;
    }));
  }

  aboutToDisappear(): void {
    for (const s of this.streams) {
      s.cancel();
    }
    this.streams = [];
  }

  private reload(s: Scene): void {
    const e = AppServices.get().engine;
    const ck = s.id + ':' + String(s.selected.id) + ':' + s.source + ':' + (s.nodeFilter ?? '');
    if (ck !== this.candidatesKey) {
      this.candidatesKey = ck;
      e.sceneCandidates(s.id).then((l: NodeSummary[]) => {
        if (this.candidatesKey === ck) {
          this.candidates = SceneSheetModel.sortByLatency(l);
        }
      }).catch(() => {
        this.candidates = [];
      });
    }
    const pooled = SceneSheetModel.pooled(s);
    const fk = s.id + ':' + String(s.testedAt ?? 0) + ':' + s.source + ':' + (s.nodeFilter ?? '');
    if (fk !== this.funnelKey) {
      this.funnelKey = fk;
      if (!pooled) {
        this.funnel = undefined;
        return;
      }
      const ttl = SceneSheetModel.funnelMaxAgeMs(e.settings().value);
      e.nodeFunnel(ttl, 300).then((f: NodeFunnel | undefined) => {
        if (this.funnelKey === fk) {
          this.funnel = f;
        }
      }).catch(() => {
        this.funnel = undefined;
      });
    }
    this.now = Date.now();
  }

  private str(r: Resource, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, ...args) : '';
    } catch (e) {
      return '';
    }
  }

  private plural(r: Resource, n: number, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getIntPluralStringValueSync(r.id, n, ...args) : '';
    } catch (e) {
      return '';
    }
  }

  private ledeText(s: Scene): string | undefined {
    const l: Lede = SceneSheetModel.lede(SceneSheetModel.pooled(s), this.funnel, this.subs, this.candidates.length);
    if (l.kind === LedeKind.POOL) {
      return this.str($r('app.string.scene_tested_from_pool'), l.sources, Format.grouped(l.pool));
    }
    if (l.kind === LedeKind.SOURCES) {
      return this.plural($r('app.plural.scene_tested_from'), l.sources, l.sources);
    }
    return undefined;
  }

  private frequency(): string {
    const st = this.settings;
    const hours = st !== undefined ? SceneSheetModel.retestHours(st) : 24;
    const base = hours === 24 ? this.str($r('app.string.scene_test_daily')) :
      this.plural($r('app.plural.scene_test_every_hours'), hours, hours);
    return st !== undefined && st.testOnWifiOnly ? this.str($r('app.string.scene_test_wifi_only'), base) : base;
  }

  private note(s: Scene): string {
    const note = this.str($r('app.string.scene_note'));
    if (s.testedAt === undefined) {
      return note;
    }
    const p = Format.ago(s.testedAt, this.now);
    const r = Labels.ago(p);
    const ago = p.count > 0 ? this.str(r, p.count) : this.str(r);
    return this.str($r('app.string.scene_note_tested'), note, ago);
  }

  private setSource(s: Scene, i: number): void {
    const want = i === 1 ? SceneSource.AUTO : SceneSource.SUBSCRIPTION_GROUP;
    if (SceneSheetModel.pooled(s) === (i === 1)) {
      return;
    }
    AppServices.get().engine.setSceneSource(s.id, want).catch(() => {});
    if (SceneSheetModel.closesAfterSource(s, want)) {
      this.onClose();
    }
  }

  private retest(s: Scene): void {
    if (this.retesting) {
      return;
    }
    this.retesting = true;
    AppServices.get().engine.retestScene(s.id).then(() => {
      Haptics.play(HapticKind.SUCCESS);
    }).catch(() => {}).finally(() => {
      this.retesting = false;
    });
  }

  build() {
    Scroll() {
      if (this.scene !== undefined) {
        this.content(this.scene)
      }
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  content(s: Scene) {
    Column() {
      Row({ space: 8 }) {
        // Android：type.number（ExtraLight + tnum）放大到 hero × 0.8。
        Text(String(s.available))
          .attributeModifier(ZHero.hero(45))
          .fontColor($r('app.color.screen_t1'))
        Text($r('app.plural.scene_available_unit', s.available))
          .fontSize(16)
          .fontColor($r('app.color.screen_t3'))
          .margin({ bottom: 8 })
      }
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 22, right: 22 })
      .accessibilityGroup(true)

      if (this.ledeText(s) !== undefined) {
        Text(this.ledeText(s))
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 22, right: 22 })
      }

      Column() {
        ZSegmented({
          options: [$r('app.string.common_source_group'), $r('app.string.common_source_auto')],
          selected: SceneSheetModel.pooled(s) ? 1 : 0,
          onSelect: (i: number) => this.setSource(s, i)
        })
      }
      .padding({ left: 16, right: 16 })
      .margin({ top: 16 })

      if (SceneSheetModel.showFunnel(SceneSheetModel.pooled(s), this.funnel) && this.funnel !== undefined) {
        Column() {
          SceneFunnel({ funnel: this.funnel })
        }
        .margin({ top: 18, bottom: 6 })
      }

      Column({ space: 12 }) {
        if (this.candidates.length > 0) {
          // 规范 §9.6 / J-6：候选列表顶部的延迟刻度条（200 ms 阈值）。
          Column() {
            LatencyTickBar({ candidates: this.candidates, selectedId: s.selected.id })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
          this.pool(s)
        }
        this.settingsGroup(s)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 12 })

      Text(this.note(s))
        .fontSize(13)
        .fontColor($r('app.color.screen_t3'))
        .padding({ left: 22, right: 22, top: 12, bottom: 24 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  row(title: ResourceStr, value: ResourceStr | undefined, divider: boolean, current: boolean, tappable: boolean,
    onTap: () => void) {
    Column() {
      Row({ space: 8 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (value !== undefined) {
          Text(value)
            .fontSize(16)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (current) {
          Text($r('app.string.common_current'))
            .fontSize(13)
            .fontColor(this.theme.accentColor())
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      if (divider) {
        Divider().strokeWidth(1).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(20) })
      }
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityRole(tappable ? AccessibilityRoleType.BUTTON : AccessibilityRoleType.TEXT)
    .stateStyles({ pressed: { .backgroundColor(tappable ? $r('app.color.screen_pressed') : Color.Transparent) }, normal: { .backgroundColor(Color.Transparent) } })
    .onClick(() => {
      if (tappable) {
        onTap();
      }
    })
  }

  private candidateValue(s: Scene, n: NodeSummary): string | undefined {
    const parts: string[] = [];
    const app = SceneSheetModel.pinnedApp(s, n);
    if (app !== undefined) {
      parts.push(this.str($r('app.string.scene_pinned_for'), app));
    }
    if (n.latencyMs !== undefined && n.latencyMs >= 0) {
      parts.push(n.latencyMs + ' ms');
    }
    return parts.length > 0 ? parts.join('  ') : undefined;
  }

  @Builder
  pool(s: Scene) {
    Column() {
      ForEach(SceneSheetModel.shownPool(this.candidates), (n: NodeSummary, i: number) => {
        this.row(n.name, this.candidateValue(s, n), i < SceneSheetModel.shownPool(this.candidates).length - 1,
          n.id === s.selected.id, n.id !== s.selected.id, () => this.onPick(s, n))
      }, (n: NodeSummary) => String(n.id) + ':' + String(n.latencyMs ?? -2) + ':' + String(s.selected.id))
    }
    .width('100%')
    .borderRadius(24)
    .clip(true)
    .backgroundColor($r('app.color.screen_s2'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
  }

  @Builder
  settingsGroup(s: Scene) {
    Column() {
      this.row($r('app.string.scene_when_unavailable'), SceneSheetModel.asksOnFailure(s) ? $r('app.string.scene_ask') :
        $r('app.string.scene_auto_switch'), true, false, false, () => {})
      if (s.nodeFilter === 'uhd') {
        this.row($r('app.string.scene_node_scope'), $r('app.string.scene_uhd_only'), true, false, false, () => {})
      }
      ForEach(s.exceptions, (e: SceneException) => {
        this.row(e.app, $r('app.string.scene_pinned_value', e.node.name), true, false, false, () => {})
      }, (e: SceneException) => e.appId + ':' + String(e.node.id))
      this.row($r('app.string.scene_test_frequency'), this.frequency(), true, false, false, () => {})
      this.row(this.retesting ? $r('app.string.common_retesting') : ZTerm.testAgain, undefined, false, false,
        !this.retesting, () => this.retest(s))
    }
    .width('100%')
    .borderRadius(24)
    .clip(true)
    .backgroundColor($r('app.color.screen_s2'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
  }
}
