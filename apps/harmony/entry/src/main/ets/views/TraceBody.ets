/*
 * 连接轨迹（M1-8 最小版 / U12，原型 trace；对照 Android ui/activity/TraceSheet.kt TraceBody、iOS Activity/TraceView）：
 * 域名（细体大字）+ “刚刚 · N 个连接 · 字节”，四步 规则 → 场景 → 节点 → 出口（竖线 + 圆点，末步实心绿，逐步淡入），
 * 下面“本次连接”覆写分段（不变 · 直连 · 其他场景，overrideHost），失败显示我们自己的文案；成功出撤销吐司（审计 U27）；
 * “始终应用”开关 = persistent。
 * 由指令面板“X 走哪里？”与最近连接（ActivitySheet，M1-8）打开（在各自 sheet 内原地显示）。还没有连接记录的输入退回规则测试（TraceModel.fromRuleTrace），
 * 只读、不给覆写。
 */
import { AppServices } from '../app/AppServices';
import { HapticKind, Haptics } from '../app/Haptics';
import { TraceChoice, TraceModel, TraceResult } from '../app/TraceModel';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { ZSegmented } from '../components/ZSegmented';
import { ZToggleRow } from '../components/ZToggleRow';
import { ConnectionTrace, RuleTrace, Scene, TraceOverride, TraceTarget } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

class TraceStep {
  index: number;
  label: ResourceStr;
  value: string;
  detail: string | undefined;
  mono: boolean;
  last: boolean;

  constructor(index: number, label: ResourceStr, value: string, detail: string | undefined, mono: boolean, last: boolean) {
    this.index = index;
    this.label = label;
    this.value = value;
    this.detail = detail;
    this.mono = mono;
    this.last = last;
  }
}

@ComponentV2
export struct TraceBody {
  @Param @Require host: string;

  @Local result: TraceResult | undefined = undefined;
  @Local failed: boolean = false;
  @Local scenes: Scene[] = [];
  @Local overrideError: boolean = false;
  @Local shown: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private streams: StreamSub[] = [];
  private timer: number = -1;

  aboutToAppear(): void {
    this.streams.push(AppServices.get().engine.scenes().subscribe((s: Scene[]) => {
      this.scenes = s;
    }));
    this.load();
  }

  aboutToDisappear(): void {
    for (const s of this.streams) {
      s.cancel();
    }
    this.streams = [];
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private load(): void {
    const e = AppServices.get().engine;
    const host = this.host;
    e.connectionTrace(host).then((t: ConnectionTrace) => {
      this.show(new TraceResult(t, true));
    }).catch(() => {
      e.testRule(host).then((r: RuleTrace) => {
        this.show(new TraceResult(TraceModel.fromRuleTrace(r), false));
      }).catch(() => {
        this.failed = true;
      });
    });
  }

  private show(r: TraceResult): void {
    const first = this.result === undefined;
    this.result = r;
    if (first) {
      this.timer = setTimeout(() => {
        this.timer = -1;
        this.shown = true;
      }, 16);
    }
  }

  private str(r: Resource, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, ...args) : '';
    } catch (e) {
      return '';
    }
  }

  private resolve(r: ResourceStr): string {
    return typeof r === 'string' ? r : this.str(r as Resource);
  }

  private plural(r: Resource, n: number, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getIntPluralStringValueSync(r.id, n, ...args) : '';
    } catch (e) {
      return '';
    }
  }

  private sceneLabel(id: string): string {
    const s = this.scenes.find((x: Scene) => x.id === id);
    return s !== undefined ? this.resolve(Labels.sceneName(s)) : id;
  }

  private meta(t: ConnectionTrace): string {
    const p = Format.ago(t.lastSeenAt, Date.now());
    const r = Labels.ago(p);
    const ago = p.count > 0 ? this.str(r, p.count) : this.str(r);
    return [ago, this.plural($r('app.plural.trace_connections'), t.connections, t.connections),
      Format.bytesText(t.totalBytes)].join(' · ');
  }

  private steps(t: ConnectionTrace): TraceStep[] {
    const out: TraceStep[] = [];
    out.push(new TraceStep(0, ZTerm.rule, TraceModel.ruleText(t.rule),
      t.ruleSource !== undefined ? this.str($r('app.string.trace_from'), t.ruleSource) : undefined, true, false));
    out.push(new TraceStep(1, ZTerm.scene, t.scene !== undefined ? this.sceneLabel(t.scene) :
      this.str($r('app.string.common_direct')), t.sceneSource, false, false));
    const node = t.node;
    if (node !== undefined) {
      out.push(new TraceStep(2, ZTerm.node, node.name,
        t.via !== undefined ? this.str($r('app.string.trace_via'), t.via) : undefined, false, false));
    }
    const parts: string[] = [];
    if (t.exitRegion !== undefined) {
      parts.push(t.exitRegion);
    }
    if (t.exitStableDays !== undefined) {
      parts.push(this.plural($r('app.plural.trace_exit_stable'), t.exitStableDays, t.exitStableDays));
    }
    out.push(new TraceStep(3, ZTerm.exit, t.exitIp ?? this.str($r('app.string.common_local_network')),
      parts.length > 0 ? parts.join(' · ') : undefined, t.exitIp !== undefined, true));
    return out;
  }

  private options(others: Scene[]): ResourceStr[] {
    const o: ResourceStr[] = [$r('app.string.trace_option_unchanged'), $r('app.string.common_direct')];
    for (const s of others) {
      o.push(Labels.sceneName(s));
    }
    return o;
  }

  private apply(t: ConnectionTrace, i: number, keep: boolean): void {
    const others = TraceModel.otherScenes(this.scenes, t.scene);
    const c: TraceChoice = TraceModel.choiceAt(i, others);
    const before: TraceOverride = TraceModel.undoChoice(t.override);
    const e = AppServices.get().engine;
    const host = t.host;
    const label = this.resolve(this.options(others)[Math.min(i, others.length + 1)]);
    e.overrideHost(host, c.target, c.sceneId, keep).then(() => {
      this.overrideError = false;
      Haptics.play(HapticKind.SUCCESS);
      const msg = c.target === TraceTarget.UNCHANGED ? this.str($r('app.string.trace_override_cleared'), host) :
        c.target === TraceTarget.DIRECT ? this.str($r('app.string.trace_override_direct'), host) :
        this.str($r('app.string.trace_override_scene'), host, label);
      AppServices.get().toasts.show(msg, {
        onUndo: () => {
          e.overrideHost(host, before.target, before.sceneId, before.persistent).then(() => this.load()).catch(() => {});
        }
      });
      this.load();
    }).catch(() => {
      this.overrideError = true;
      this.load();
    });
  }

  build() {
    Column() {
      if (this.result !== undefined) {
        this.content(this.result)
      } else if (this.failed) {
        Text($r('app.string.trace_override_error'))
          .fontSize(14)
          .fontColor($r('app.color.screen_t3'))
          .padding({ left: 22, right: 22, top: 12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  content(r: TraceResult) {
    Column() {
      Column() {
        Text(r.trace.host)
          .fontSize(32)
          .fontWeight(FontWeight.Lighter)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.screen_t1'))
        if (r.observed) {
          Text(this.meta(r.trace))
            .fontSize(14)
            .fontColor($r('app.color.screen_t3'))
        }
        Column() {
          ForEach(this.steps(r.trace), (s: TraceStep) => {
            this.step(s)
          }, (s: TraceStep) => String(s.index) + ':' + s.value)
        }
        .margin({ top: 24 })
      }
      .padding({ left: 22, right: 22 })
      .alignItems(HorizontalAlign.Start)

      if (r.observed) {
        this.overrides(r.trace)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  step(s: TraceStep) {
    Row({ space: 16 }) {
      Column() {
        Circle({ width: 11, height: 11 })
          .margin({ top: 2 })
          .fill(s.last ? $r('app.color.screen_green') : Color.Transparent)
          .stroke(s.last ? $r('app.color.screen_green') : $r('app.color.screen_t3'))
          .strokeWidth(1.5)
        if (!s.last) {
          Column()
            .width(1)
            .layoutWeight(1)
            .backgroundColor($r('app.color.screen_hl2'))
        }
      }
      .width(20)
      .alignSelf(ItemAlign.Stretch)

      Column({ space: 2 }) {
        Text(s.label)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
        Text(s.value)
          .fontSize(17)
          .fontFamily(s.mono ? 'monospace' : 'HarmonyOS Sans')
          .fontColor($r('app.color.screen_t1'))
        if (s.detail !== undefined) {
          Text(s.detail)
            .fontSize(14)
            .fontColor($r('app.color.screen_t3'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 22 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .opacity(this.shown ? 1 : 0)
    .translate({ x: this.shown ? 0 : -8 })
    .animation({ duration: 400, delay: 80 + s.index * 60, curve: Curve.EaseOut })
    .accessibilityGroup(true)
  }

  @Builder
  overrides(t: ConnectionTrace) {
    Column() {
      Text($r('app.string.trace_this_connection'))
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
        .padding({ left: 26, right: 26, top: 8, bottom: 8 })
      Column() {
        ZSegmented({
          options: this.options(TraceModel.otherScenes(this.scenes, t.scene)),
          selected: TraceModel.selectedIndex(t.override, TraceModel.otherScenes(this.scenes, t.scene)),
          onSelect: (i: number) => this.apply(t, i, t.override !== undefined ? t.override.persistent : false)
        })
      }
      .padding({ left: 16, right: 16 })
      if (this.overrideError) {
        Text($r('app.string.trace_override_error'))
          .fontSize(12)
          .fontColor($r('app.color.screen_red_text'))
          .padding({ left: 26, right: 26, top: 8, bottom: 8 })
      }
      Column() {
        ZToggleRow({
          title: $r('app.string.trace_always_apply'),
          subtitle: $r('app.string.trace_always_apply_hint'),
          isOn: t.override !== undefined ? t.override.persistent : false,
          divider: false,
          onChange: (v: boolean) => this.apply(t,
            TraceModel.selectedIndex(t.override, TraceModel.otherScenes(this.scenes, t.scene)), v)
        })
      }
      .margin({ left: 16, right: 16, top: 16 })
      .borderRadius(24)
      .clip(true)
      .backgroundColor($r('app.color.screen_s2'))
      .border({ width: 1, color: $r('app.color.screen_hl') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 16, bottom: 12 })
  }
}
