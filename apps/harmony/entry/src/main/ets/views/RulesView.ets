import { LengthMetrics } from '@kit.ArkUI';
import { ZLayout } from '../generated/ZTokens';
/*
 * 规则页（对照 Android ui/rules RulesScreen）：总数 hero×0.86 + 分层摘要（engine.ruleStats）；
 * 搜索框边输边测（60 ms 去抖，engine.testRule），下方卡片是空提示或“请求 → 第 N 层 → 场景/出口 → 出口 IP”链；
 * “匹配顺序 · 从上到下”各层（名称 + 说明 + 描边类型标签 + 条数），命中层浅强调底，末行“其余流量 MATCH”。
 * 页头“+”（Index 传 addTick，同 Android PageScaffold trailing Plus）：以搜索框域名打开与轨迹页同一张 TraceBody sheet，
 * 框空时只聚焦搜索框。
 */
import { ZSheetHeader } from '../components/ZSheetHeader';
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZHero } from '../common/ZTypeMods';
import { ZCard } from '../components/ZCard';
import { LayerKind, RuleLayer, RuleStats, RuleTrace, Scene } from '../engine/Model';
import { ZTerm } from '../generated/ZTerms';
import { ZTheme } from '../common/Theme';
import { TraceBody } from './TraceBody';

/** 界面测试用组件 id。 */
export const RULES_INPUT_ID: string = 'zephyr.rules.input';

/** 链上一步（同 Android Step）：空心点 + 竖线相连，末步实心强调色点。 */
@ComponentV2
struct TraceStep {
  @Param label: ResourceStr = '';
  @Param value: string = '';
  @Param mono: boolean = false;
  @Param badge: string = '';
  @Param region: string = '';
  @Param last: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();

  build() {
    Row() {
      Stack({ alignContent: Alignment.Top }) {
        if (!this.last) {
          Column()
            .width(1)
            .height('100%')
            .margin({ top: 14 })
            .backgroundColor($r('app.color.screen_hl2'))
        }
        Circle()
          .width(9)
          .height(9)
          .margin({ top: 5 })
          .fill(this.last ? this.theme.accentColor() : Color.Transparent)
          .stroke(this.last ? this.theme.accentColor() : $r('app.color.screen_t3'))
          .strokeWidth(this.last ? 0 : 1.5)
      }
      .width(9)
      .height('100%')

      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
        Row({ space: 8 }) {
          if (this.region.length > 0) {
            Text(this.region)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontFamily('monospace')
              .fontColor($r('app.color.screen_t2'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .border({ width: 1, color: $r('app.color.screen_hl2') })
          }
          Text(this.value)
            .fontSize(15)
            .fontFamily(this.mono ? 'monospace' : 'HarmonyOS Sans')
            .fontColor($r('app.color.screen_t1'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .padding({ bottom: 12 })

      if (this.badge.length > 0) {
        Text(this.badge)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t3'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .accessibilityGroup(true)
  }
}

/** 匹配顺序一行（同 Android LayerRow）。 */
@ComponentV2
struct LayerRowView {
  @Param ix: number = 0;
  @Param name: ResourceStr = '';
  @Param note: string = '';
  @Param kind: ResourceStr | undefined = undefined;
  @Param count: string = '';
  @Param hit: boolean = false;
  @Param accent: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();

  build() {
    Row() {
      Text(String(this.ix))
        .width(24)
        .fontSize(15)
        .fontFamily('monospace')
        .fontColor(this.hit ? this.theme.accentColor() : $r('app.color.screen_t3'))
      Column({ space: 2 }) {
        Text(this.name)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.note)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.kind !== undefined) {
        Text(this.kind)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.accent ? this.theme.accentColor() : $r('app.color.screen_t2'))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(10)
          .border({ width: 1, color: this.accent ? this.theme.accentColor() : $r('app.color.screen_hl2') })
          .margin({ right: 12 })
      }
      Text(this.count)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor($r('app.color.screen_t2'))
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(this.hit ? this.theme.accentSoft() : Color.Transparent)
    .animation({ duration: 200, curve: Curve.EaseOut })
  }
}

@ComponentV2
export struct RulesView {
  /** 页头“+”点按计数（Index 传入）。 */
  @Param addTick: number = 0;
  @Local stats: RuleStats | undefined = undefined;
  @Local input: string = '';
  @Local trace: RuleTrace | undefined = undefined;
  @Local overrideHost: string = '';
  @Local showOverride: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private debounce: number = -1;
  private seq: number = 0;

  @Monitor('addTick')
  onAddTick(): void {
    this.addOverride();
  }

  /** “+”：有域名就开覆写 sheet，没有就聚焦搜索框。 */
  private addOverride(): void {
    const h = this.input.trim();
    if (h.length === 0) {
      this.getUIContext().getFocusController().requestFocus(RULES_INPUT_ID);
      return;
    }
    this.overrideHost = h;
    this.showOverride = true;
  }

  @Builder
  overrideSheet() {
    Scroll() {
      Column() {
        ZSheetHeader({
          onDone: () => {
            this.showOverride = false;
          }
        })
        if (this.overrideHost.length > 0) {
          TraceBody({ host: this.overrideHost })
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 })
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  aboutToAppear(): void {
    AppServices.get().engine.ruleStats().then((s: RuleStats) => {
      this.stats = s;
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
    }
  }

  /** 边输边测（同 Android produceState + delay(60)）；过期结果按序号丢弃。 */
  private onInput(v: string): void {
    this.input = v;
    if (this.debounce >= 0) {
      clearTimeout(this.debounce);
      this.debounce = -1;
    }
    const q = v.trim();
    const my = ++this.seq;
    if (q.length === 0) {
      this.trace = undefined;
      return;
    }
    this.debounce = setTimeout(() => {
      this.debounce = -1;
      AppServices.get().engine.testRule(q).then((t: RuleTrace) => {
        if (my === this.seq) {
          this.trace = t;
        }
      }).catch(() => {
        if (my === this.seq) {
          this.trace = undefined;
        }
      });
    }, 60);
  }

  private str(r: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id) : '';
    } catch (e) {
      return '';
    }
  }

  private resText(r: ResourceStr): string {
    return typeof r === 'string' ? r : this.str(r as Resource);
  }

  private total(): number {
    return this.stats !== undefined ? this.stats.total : 0;
  }

  private layers(): RuleLayer[] {
    return this.stats !== undefined ? this.stats.layers : [];
  }

  private layerCount(): number {
    return this.stats !== undefined ? this.stats.layers.length : 7;
  }

  private diskText(): string {
    return Format.bytesText(this.stats !== undefined ? this.stats.diskBytes : 0);
  }

  private hitLayer(t: RuleTrace): RuleLayer | undefined {
    const li = t.layerIndex;
    return li === undefined ? undefined : this.layers().find((x: RuleLayer) => x.index === li);
  }

  @Builder
  chain(t: RuleTrace) {
    Column() {
      TraceStep({ label: $r('app.string.rules_step_request'), value: t.input, mono: true })
      if (this.hitLayer(t) !== undefined) {
        TraceStep({
          label: $r('app.string.rules_step_layer', this.hitLayer(t)!.index + 1, this.hitLayer(t)!.name),
          value: t.rule,
          mono: true,
          badge: t.ruleNo !== undefined ? '#' + Format.grouped(t.ruleNo) : ''
        })
      } else {
        TraceStep({
          label: $r('app.string.rules_step_layer', this.layerCount() + 1, this.str($r('app.string.rules_other_traffic'))),
          value: 'MATCH',
          mono: true
        })
      }
      if (t.policy === 'DIRECT') {
        TraceStep({ label: ZTerm.exit, value: this.str($r('app.string.common_direct')), last: true })
      } else if (t.policy === 'REJECT') {
        TraceStep({ label: $r('app.string.rules_step_result'), value: this.str($r('app.string.rules_blocked')), last: true })
      } else if (t.scene !== undefined) {
        TraceStep({
          label: $r('app.string.rules_step_scene', this.resText(Labels.sceneName(t.scene as Scene))),
          value: (t.scene as Scene).selected.name,
          region: (t.scene as Scene).selected.region,
          last: t.exitIp === undefined
        })
        if (t.exitIp !== undefined) {
          TraceStep({ label: ZTerm.exitIp, value: t.exitIp, mono: true, last: true })
        }
      }
      Text($r('app.string.rules_took', Format.micros(t.tookMicros)))
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private kindOf(k: LayerKind): Resource {
    return Labels.layerKind(k);
  }

  build() {
    Scroll() {
      Column() {
        Row({ space: 8 }) {
          Text(Format.grouped(this.total()))
            // Android：hero × 0.86（规则数位数多）。
            .attributeModifier(ZHero.hero(48))
            .fontColor($r('app.color.screen_t1'))
          Text($r('app.plural.rules_total_unit', this.total()))
            .fontSize(16)
            .fontColor($r('app.color.screen_t3'))
            .margin({ bottom: 8 })
        }
        .alignItems(VerticalAlign.Bottom)
        .padding({ left: 22, right: 22 })
        Text($r('app.plural.rules_summary', this.layerCount(), this.layerCount(), this.diskText()))
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 22, right: 22 })

        Search({ value: this.input, placeholder: $r('app.string.rules_test_placeholder') })
          .id(RULES_INPUT_ID)
          .height(48)
          .borderRadius(16)
          .margin({ left: 16, right: 16, top: 18 })
          .backgroundColor($r('app.color.screen_s3'))
          .fontColor($r('app.color.screen_t1'))
          .placeholderColor($r('app.color.screen_t3'))
          .placeholderFont({ size: 16 })
          .textFont({ size: 16 })
          .searchIcon({ size: 20, color: $r('app.color.screen_t2') })
          .cancelButton({ style: CancelButtonStyle.INPUT })
          .type(SearchType.URL)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string) => this.onInput(v))

        Column() {
          ZCard({ pad: 18 }) {
            if (this.trace === undefined) {
              Text($r('app.string.rules_test_hint'))
                .fontSize(13)
                .fontColor($r('app.color.screen_t3'))
            } else {
              this.chain(this.trace)
            }
          }
        }
        .padding({ left: 16, right: 16, top: 12 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))

        Row() {
          Text($r('app.string.rules_match_order'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          Blank()
          Text($r('app.string.rules_top_to_bottom'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 20, bottom: 8 })

        Column() {
        Column() {
          ForEach(this.layers(), (l: RuleLayer, i: number) => {
            if (i > 0) {
              Divider().strokeWidth(1).color($r('app.color.screen_hl'))
            }
            LayerRowView({
              ix: i + 1,
              name: l.name,
              note: l.note,
              kind: this.kindOf(l.kind),
              count: Format.grouped(l.count),
              hit: this.trace !== undefined && this.trace.layerIndex === l.index,
              accent: l.kind === LayerKind.OVERRIDE
            })
          }, (l: RuleLayer) => String(l.index) + ':' + String(l.count))
          if (this.stats !== undefined) {
            Divider().strokeWidth(1).color($r('app.color.screen_hl'))
            LayerRowView({
              ix: this.layerCount() + 1,
              name: $r('app.string.rules_other_traffic'),
              note: 'MATCH',
              kind: $r('app.string.rules_kind_other'),
              count: '',
              hit: this.trace !== undefined && this.trace.layerIndex === undefined,
              accent: false
            })
          }
        }
        .width('100%')
        .borderRadius(24)
        .clip(true)
        .backgroundColor($r('app.color.screen_s2'))
        .border({ width: 1, color: $r('app.color.screen_hl') })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Text($r('app.string.rules_note'))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 22, right: 22, top: 14, bottom: 14 })
      }
      .width('100%')
      .padding({ top: 8, bottom: 40 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .bindSheet(this.showOverride, this.overrideSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: false,
      radius: LengthMetrics.vp(ZLayout.sheetRadius),
      borderWidth: { top: 1 },
      borderColor: { top: $r('app.color.screen_hl2') },
      dragBar: true,
      backgroundColor: $r('app.color.screen_s1'),
      onDisappear: () => {
        this.showOverride = false;
        this.overrideHost = '';
      }
    })
  }
}
