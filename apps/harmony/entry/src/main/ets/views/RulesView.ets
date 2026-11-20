/*
 * 规则段（对照 Android ui/rules RulesScreen，简化）：总数 + 分层摘要（engine.ruleStats），
 * 匹配顺序从上到下的各层列表，域名 / IP 测试框（engine.testRule）显示命中层、规则、策略与用时。
 */
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZSection } from '../components/ZSection';
import { ErrorCode, RuleLayer, RuleStats, RuleTrace } from '../engine/Model';
import { ZephyrError } from '../engine/ZephyrEngine';

@ComponentV2
export struct RulesView {
  @Local stats: RuleStats | undefined = undefined;
  @Local input: string = '';
  @Local trace: RuleTrace | undefined = undefined;
  @Local invalid: boolean = false;
  @Local testing: boolean = false;

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

  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.stats !== undefined) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(Format.grouped(this.total()))
                .fontSize(28)
                .fontWeight(FontWeight.Medium)
                .fontFamily('monospace')
                .fontColor($r('app.color.screen_t1'))
              Text($r('app.plural.rules_total_unit', this.total()))
                .fontSize(14)
                .fontColor($r('app.color.screen_t3'))
            }
            .alignItems(VerticalAlign.Bottom)
            Text($r('app.plural.rules_summary', this.layers().length, this.layers().length, this.diskText()))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
          .alignItems(HorizontalAlign.Start)
        }

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            TextInput({ text: this.input, placeholder: $r('app.string.rules_test_placeholder') })
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
              .fontColor($r('app.color.screen_red'))
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
                Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 44 })
              }
            }
          }, (l: RuleLayer) => String(l.index) + ':' + String(l.count))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
