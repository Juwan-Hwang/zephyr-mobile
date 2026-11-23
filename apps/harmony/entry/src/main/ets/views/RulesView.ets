import { LengthMetrics } from '@kit.ArkUI';
/*
 * 规则段（对照 Android ui/rules RulesScreen，简化）：总数 + 分层摘要（engine.ruleStats），
 * 匹配顺序从上到下的各层列表，域名 / IP 测试框（engine.testRule）显示命中层、规则、策略与用时。
 * 右上“+”（M1-13，同 Android Review L-P2-8）：以测试框里的域名为对象，打开与轨迹页同一张 TraceBody sheet
 * （目标 / 场景 / 保留覆写）；测试框为空时只把焦点给测试框。
 */
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZHero } from '../common/ZTypeMods';
import { ZCard } from '../components/ZCard';
import { ZSection } from '../components/ZSection';
import { ErrorCode, RuleLayer, RuleStats, RuleTrace } from '../engine/Model';
import { ZephyrError } from '../engine/ZephyrEngine';
import { ZTerm } from '../generated/ZTerms';
import { ZTheme } from '../common/Theme';
import { TraceBody } from './TraceBody';

/** 界面测试用组件 id。 */
export const RULES_ADD_ID: string = 'zephyr.rules.add';
export const RULES_INPUT_ID: string = 'zephyr.rules.input';

@ComponentV2
export struct RulesView {
  @Local stats: RuleStats | undefined = undefined;
  @Local input: string = '';
  @Local trace: RuleTrace | undefined = undefined;
  @Local invalid: boolean = false;
  @Local testing: boolean = false;
  @Local overrideHost: string = '';
  @Local showOverride: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();

  /** “+”：有域名就开覆写 sheet，没有就聚焦测试框。 */
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

  private runTest(): void {
    const q = this.input.trim();
    if (q.length === 0 || this.testing) {
      return;
    }
    this.testing = true;
    AppServices.get().engine.testRule(q).then((t: RuleTrace) => {
      this.trace = t;
      this.invalid = false;
    }).catch((e: Object) => {
      this.trace = undefined;
      this.invalid = ZephyrError.from(e).code === ErrorCode.RULE_INPUT_INVALID;
    }).finally(() => {
      this.testing = false;
    });
  }

  private total(): number {
    return this.stats !== undefined ? this.stats.total : 0;
  }

  private layers(): RuleLayer[] {
    return this.stats !== undefined ? this.stats.layers : [];
  }

  private diskText(): string {
    return this.stats !== undefined ? Format.bytesText(this.stats.diskBytes) : '';
  }

  private layerTitle(t: RuleTrace): string {
    if (t.layerIndex === undefined) {
      return 'MATCH';
    }
    const idx = t.layerIndex;
    const l = this.layers().find((x: RuleLayer) => x.index === idx);
    return l !== undefined ? l.name : String(idx);
  }

  @Builder
  traceCard(t: RuleTrace) {
    ZCard() {
      Column({ space: 6 }) {
        Text(t.input)
          .fontSize(15)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t1'))
        Text(t.layerIndex !== undefined ? $r('app.string.rules_step_layer', t.layerIndex + 1, this.layerTitle(t))
          : $r('app.string.rules_other_traffic'))
          .fontSize(13)
          .fontColor($r('app.color.screen_t2'))
        Text(t.rule)
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t2'))
        Row({ space: 6 }) {
          Text($r('app.string.rules_step_result'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          if (t.scene !== undefined) {
            Text(Labels.sceneName(t.scene))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.screen_t1'))
          } else {
            Text(t.policy)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.screen_t1'))
          }
          if (t.exitIp !== undefined) {
            Text('· ' + t.exitIp)
              .fontSize(13)
              .fontFamily('monospace')
              .fontColor($r('app.color.screen_t3'))
          }
        }
        Text($r('app.string.rules_took', Format.micros(t.tookMicros)))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  statsHeader() {
    if (this.stats !== undefined) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(Format.grouped(this.total()))
            // Android：hero × 0.86（规则数位数多）。
            .attributeModifier(ZHero.hero(48))
            .fontColor($r('app.color.screen_t1'))
          Text($r('app.plural.rules_total_unit', this.total()))
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
            .margin({ bottom: 8 })
        }
        .alignItems(VerticalAlign.Bottom)
        Text($r('app.plural.rules_summary', this.layers().length, this.layers().length, this.diskText()))
          .fontSize(13)
          .fontColor($r('app.color.screen_t3'))
      }
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          this.statsHeader()
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([this.theme.accentColor()])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.rules_add_override_a11y'))
          .id(RULES_ADD_ID)
          .onClick(() => this.addOverride())
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            TextInput({ text: this.input, placeholder: $r('app.string.rules_test_placeholder') })
              .id(RULES_INPUT_ID)
              .layoutWeight(1)
              .height(40)
              .type(InputType.URL)
              .enterKeyType(EnterKeyType.Search)
              .backgroundColor($r('app.color.screen_s3'))
              .fontColor($r('app.color.screen_t1'))
              .onChange((v: string) => {
                this.input = v;
                this.invalid = false;
              })
              .onSubmit(() => this.runTest())
            Button($r('app.string.hm_rules_test'))
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.screen_on_primary'))
              .backgroundColor($r('app.color.screen_primary'))
              .enabled(this.input.trim().length > 0 && !this.testing)
              .onClick(() => this.runTest())
          }
          if (this.invalid) {
            Text($r('app.string.rules_test_hint'))
              .fontSize(12)
              .fontColor($r('app.color.screen_red_text'))
          } else if (this.trace === undefined) {
            Text($r('app.string.rules_test_hint'))
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
          }
        }
        .alignItems(HorizontalAlign.Start)

        if (this.trace !== undefined) {
          this.traceCard(this.trace)
        }

        ZSection({ header: $r('app.string.rules_match_order'), footer: $r('app.string.rules_note') }) {
          ForEach(this.layers(), (l: RuleLayer, i: number) => {
            Column() {
              Row({ space: 10 }) {
                Text(String(l.index + 1))
                  .fontSize(13)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.screen_t3'))
                  .width(18)
                Column({ space: 2 }) {
                  Text(l.name)
                    .fontSize(15)
                    .fontColor($r('app.color.screen_t1'))
                  Text(Labels.layerKind(l.kind))
                    .fontSize(12)
                    .fontColor($r('app.color.screen_t3'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(Format.grouped(l.count))
                  .fontSize(13)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.screen_t2'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              if (i < this.layers().length - 1) {
                Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(44) })
              }
            }
          }, (l: RuleLayer) => String(l.index) + ':' + String(l.count))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .bindSheet(this.showOverride, this.overrideSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.screen_bg'),
      onDisappear: () => {
        this.showOverride = false;
        this.overrideHost = '';
      }
    })
  }
}
