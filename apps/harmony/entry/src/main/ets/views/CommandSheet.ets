/*
 * “搜索或输入指令”面板（原型 cmdv，index.html 879 / 1020–1061；对照 Android CommandOverlay、iOS CommandView；契约 §16.d）。
 * 首页底栏指令栏点开（bindSheet）。
 * - 空输入：“建议”示例短语，点按只填入输入框并重新解析，不直接执行（U24）。
 * - 有输入：token 下划线预览（服务蓝 / 地区绿 / 操作琥珀）、解析卡片（服务 / 范围 / 地区 / 操作）、
 *   一张预览卡（含出口 IP 行），点“应用”（或回车）才执行，执行后出撤销吐司（§16.e⑥）。
 *   “视频只用 4K 节点”出 4K 卡（§15.h，同 Android CommandPlan.Uhd）：N 个中 M 个支持 4K / 当前节点保持 / 将使用 X /
 *   尚未测速 / 没有支持 4K 的节点（按钮禁用）/ 已过滤时“使用全部节点”。
 * - 只有地区或普通文本：节点结果（最快前 5 个 + 查看全部）；像域名 / IP：“X 走哪里？”→ 面板内原地显示连接轨迹
 *   （TraceBody，规则 → 场景 → 节点 → 出口 + 覆写；没有连接记录时退回规则测试）。Android / iOS 此行去规则页测试，
 *   鸿蒙按 #241 指派改为轨迹（规则页仍在资料库）。
 */
import { AppServices } from '../app/AppServices';
import { CommandPlan, CommandPlanKind, CommandPlanner } from '../app/CommandPlanner';
import { Haptics, HapticKind } from '../app/Haptics';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { CommandAct, CommandParser, CommandSpan, CommandTok, ParsedCommand } from '../engine/CommandParser';
import { NodeQueryResult, NodeSummary } from '../engine/Model';
import { ZTerm } from '../generated/ZTerms';
import { TraceBody } from './TraceBody';

/** 预览里的一段文字（token 或普通文本）。 */
class Piece {
  text: string;
  kind: CommandTok | undefined;

  constructor(text: string, kind: CommandTok | undefined) {
    this.text = text;
    this.kind = kind;
  }
}

class Chip {
  label: Resource;
  value: string;

  constructor(label: Resource, value: string) {
    this.label = label;
    this.value = value;
  }
}

const PLAN_DEBOUNCE_MS: number = 80;
const NODES_DEBOUNCE_MS: number = 120;

export function commandRegionName(code: string): Resource {
  switch (code) {
    case 'JP':
      return $r('app.string.command_region_jp');
    case 'US':
      return $r('app.string.command_region_us');
    case 'HK':
      return $r('app.string.command_region_hk');
    case 'SG':
      return $r('app.string.command_region_sg');
    case 'TW':
      return $r('app.string.command_region_tw');
    case 'GB':
      return $r('app.string.command_region_gb');
    case 'KR':
      return $r('app.string.command_region_kr');
    default:
      return $r('app.string.command_region_de');
  }
}

@ComponentV2
export struct CommandSheet {
  /** 查看全部节点（节点页，查询 = 地区代码 / 输入）。 */
  @Event onOpenNodes: (query: string) => void = (query: string) => {};
  /** 测试规则（规则页）。 */
  @Event onOpenRules: () => void = () => {};
  /** 应用后收起面板。 */
  @Event onDone: () => void = () => {};

  @Local input: string = '';
  @Local parsed: ParsedCommand = CommandParser.parse('');
  @Local plan: CommandPlan | undefined = undefined;
  @Local nodes: NodeSummary[] = [];
  @Local nodeTotal: number = 0;
  @Local applying: boolean = false;
  /** “X 走哪里？”点开后在面板内原地显示的连接轨迹（M1-8 最小版）；'' = 不显示。 */
  @Local traceHost: string = '';
  @Local theme: ZTheme = ZTheme.shared();

  private planner: CommandPlanner = new CommandPlanner(AppServices.get().engine);
  private planTimer: number = -1;
  private nodesTimer: number = -1;
  private seq: number = 0;

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.planTimer >= 0) {
      clearTimeout(this.planTimer);
      this.planTimer = -1;
    }
    if (this.nodesTimer >= 0) {
      clearTimeout(this.nodesTimer);
      this.nodesTimer = -1;
    }
  }

  private setInput(v: string): void {
    this.input = v;
    this.parsed = CommandParser.parse(v);
    this.plan = undefined;
    this.nodes = [];
    this.nodeTotal = 0;
    this.clearTimers();
    this.seq++;
    const mine = this.seq;
    if (v.trim().length === 0) {
      return;
    }
    const p = this.parsed;
    this.planTimer = setTimeout(() => {
      this.planTimer = -1;
      this.planner.plan(p).then((r: CommandPlan | undefined) => {
        if (mine === this.seq) {
          this.plan = r;
        }
      }).catch(() => {});
    }, PLAN_DEBOUNCE_MS);
    if (!p.hasChips && !CommandPlanner.looksLikeHost(v)) {
      const q = p.region !== undefined ? p.region.code : v.trim();
      this.nodesTimer = setTimeout(() => {
        this.nodesTimer = -1;
        this.loadNodes(q, mine);
      }, NODES_DEBOUNCE_MS);
    }
  }

  private loadNodes(q: string, mine: number): void {
    const engine = AppServices.get().engine;
    engine.queryNodes(q).then((r: NodeQueryResult) => {
      if (mine !== this.seq || r.total === 0) {
        return;
      }
      this.nodeTotal = r.total;
      engine.nodeRows(r.token, 0, 6).then((page) => {
        if (mine === this.seq) {
          this.nodes = page.rows.filter((n: NodeSummary) => n.id >= 0).slice(0, 5);
        }
      }).catch(() => {});
    }).catch(() => {});
  }

  private str(r: ResourceStr, ...args: (string | number)[]): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return typeof r === 'string' ? r : '';
      }
      if (typeof r === 'string') {
        return r;
      }
      return ctx.resourceManager.getStringSync((r as Resource).id, ...args);
    } catch (e) {
      return typeof r === 'string' ? r : '';
    }
  }

  private examples(): string[] {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx !== undefined) {
        return ctx.resourceManager.getStringArrayValueSync($r('app.strarray.command_examples').id);
      }
    } catch (e) {
      // 退回原型中文示例。
    }
    return ['Gemini 走日本', 'GitHub 直连', '视频只用 4K 节点', '香港'];
  }

  /** 计划的主语：服务名，场景词时用场景名（U6：内置场景用界面语言）。 */
  private who(p: CommandPlan): string {
    if (p.isSceneWord && p.scene !== undefined) {
      return this.str(Labels.sceneName(p.scene));
    }
    return p.serviceName;
  }

  private pieces(): Piece[] {
    const out: Piece[] = [];
    let at = 0;
    for (const s of this.parsed.spans) {
      if (s.start > at) {
        out.push(new Piece(this.input.substring(at, s.start), undefined));
      }
      out.push(new Piece(this.input.substring(s.start, s.start + s.length), s.kind));
      at = s.start + s.length;
    }
    if (at < this.input.length) {
      out.push(new Piece(this.input.substring(at), undefined));
    }
    return out;
  }

  private tokColor(k: CommandTok | undefined): ResourceColor {
    if (k === CommandTok.SERVICE) {
      return this.theme.accentColor();
    }
    if (k === CommandTok.REGION) {
      return $r('app.color.screen_green');
    }
    if (k === CommandTok.ACTION) {
      return $r('app.color.screen_amber');
    }
    return $r('app.color.screen_t1');
  }

  private chips(): Chip[] {
    const p = this.parsed;
    const out: Chip[] = [];
    if (p.service !== undefined) {
      out.push(new Chip(p.service.isSceneWord ? $r('app.string.command_chip_scene') : $r('app.string.command_chip_service'),
        p.service.isSceneWord ? this.str(p.service.scope === '视频' ? $r('app.string.common_scene_video') : p.service.name) :
        p.service.name));
      if (!p.service.isSceneWord) {
        const scope = p.service.scope === 'AI' ? 'AI' : this.str(p.service.scope === '视频' ?
          $r('app.string.common_scene_video') : $r('app.string.common_scene_other'));
        out.push(new Chip($r('app.string.command_chip_scope'), scope));
      }
    }
    if (p.region !== undefined) {
      out.push(new Chip($r('app.string.command_chip_region'), this.str(commandRegionName(p.region.code))));
    }
    if (p.act !== undefined) {
      out.push(new Chip($r('app.string.command_chip_action'), p.act === CommandAct.DIRECT ?
        this.str(ZTerm.modeDirect) : '4K'));
    }
    return out;
  }

  private apply(): void {
    const p = this.plan;
    if (p === undefined || !p.applicable || this.applying) {
      return;
    }
    this.applying = true;
    const who = this.who(p);
    const toastText = this.toastText(p, who);
    this.planner.apply(p).then((undo: () => Promise<void>) => {
      Haptics.play(HapticKind.SUCCESS);
      AppServices.get().toasts.show(toastText, {
        onUndo: () => {
          undo().catch(() => {});
        }
      });
      this.onDone();
    }).catch((e: Object) => {
      AppServices.get().toasts.show(this.str($r('app.string.home_apply_failed'), who));
    }).finally(() => {
      this.applying = false;
    });
  }

  private toastText(p: CommandPlan, who: string): string {
    if (p.kind === CommandPlanKind.DIRECT) {
      return this.str($r('app.string.home_now_direct'), who);
    }
    if (p.kind === CommandPlanKind.UHD) {
      if (p.clear) {
        return this.str($r('app.string.home_now_all_nodes'), who);
      }
      const to = p.uhdTarget;
      return to !== undefined ? this.str($r('app.string.home_now_uses_uhd'), who, to.name) :
        this.str($r('app.string.home_now_uhd_only'), who);
    }
    return this.str($r('app.string.home_now_uses'), who, p.node !== undefined ? p.node.name : '');
  }

  /** 4K 卡的说明行（同 Android CommandOverlay CommandPlan.Uhd 的 when 分支）。 */
  private uhdNote(p: CommandPlan): ResourceStr {
    const pv = p.preview;
    if (p.clear) {
      return $r('app.string.command_uhd_clear_note', p.scene !== undefined ? this.str(Labels.sceneName(p.scene)) : '');
    }
    if (pv === undefined || pv.poolMatching === 0) {
      return $r('app.string.command_uhd_none');
    }
    if (pv.matching === 0) {
      return $r('app.plural.command_uhd_untested', pv.poolMatching, pv.poolMatching);
    }
    if (pv.currentKept) {
      return $r('app.plural.command_uhd_matching_keep', pv.matching, pv.total, pv.matching);
    }
    return $r('app.plural.command_uhd_matching_switch', pv.matching, pv.total, pv.matching,
      pv.suggested !== undefined ? pv.suggested.name : this.str($r('app.string.command_uhd_fastest')));
  }

  build() {
    if (this.traceHost.length > 0) {
      this.traceStep()
    } else {
      this.commandStep()
    }
  }

  /** 轨迹（原地一步，同 Android 最近连接里原地显示轨迹，H-P2-9）：左上“返回指令”回到输入。 */
  @Builder
  traceStep() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 4 }) {
          Text('‹')
            .fontSize(22)
            .fontColor(this.theme.accentColor())
            .accessibilityLevel('no')
          Text($r('app.string.common_back_to', this.str($r('app.string.command_section_command'))))
            .fontSize(15)
            .fontColor(this.theme.accentColor())
        }
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .accessibilityGroup(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => {
          this.traceHost = '';
        })
        TraceBody({ host: this.traceHost })
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  commandStep() {
    Scroll() {
      Column({ space: 14 }) {
        TextInput({ text: this.input, placeholder: $r('app.string.command_placeholder') })
          .defaultFocus(true)
          .enterKeyType(EnterKeyType.Go)
          .height(48)
          .borderRadius(14)
          .backgroundColor($r('app.color.screen_cmd_bg'))
          .accessibilityText($r('app.string.command_placeholder'))
          .onChange((v: string) => this.setInput(v))
          .onSubmit(() => this.apply())

        if (this.input.trim().length === 0) {
          this.suggestions()
        } else {
          if (this.parsed.spans.length > 0) {
            this.tokenPreview()
          }
          if (this.parsed.hasChips) {
            this.chipRow()
          }
          if (this.plan !== undefined) {
            this.planCard(this.plan)
          }
          if (CommandPlanner.looksLikeHost(this.input)) {
            this.testRuleRow()
          }
          if (this.nodes.length > 0) {
            this.nodeResults()
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  sectionTitle(r: Resource) {
    Text(r)
      .fontSize(13)
      .fontColor($r('app.color.screen_t3'))
  }

  @Builder
  suggestions() {
    Column({ space: 4 }) {
      this.sectionTitle($r('app.string.command_section_suggestions'))
      ForEach(this.examples(), (s: string) => {
        Text(s)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .onClick(() => this.setInput(s))
      }, (s: string) => s)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 输入的 token 化回显：服务蓝、地区绿、操作琥珀，带下划线（原型 .tk.s / .r / .a）。 */
  @Builder
  tokenPreview() {
    Text() {
      ForEach(this.pieces(), (pc: Piece) => {
        if (pc.kind !== undefined) {
          Span(pc.text)
            .fontColor(this.tokColor(pc.kind))
            .decoration({ type: TextDecorationType.Underline, color: this.tokColor(pc.kind) })
        } else {
          Span(pc.text).fontColor($r('app.color.screen_t2'))
        }
      }, (pc: Piece, i: number) => i + ':' + pc.text)
    }
    .fontSize(15)
    .accessibilityLevel('no')
  }

  @Builder
  chipRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.chips(), (c: Chip) => {
        Column({ space: 2 }) {
          Text(c.label).fontSize(11).fontColor($r('app.color.screen_t3'))
          Text(c.value).fontSize(14).fontColor($r('app.color.screen_t1')).fontWeight(FontWeight.Medium)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .margin({ right: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor($r('app.color.screen_s1'))
        .accessibilityGroup(true)
      }, (c: Chip) => c.value)
    }
    .width('100%')
  }

  @Builder
  planCard(p: CommandPlan) {
    Column({ space: 8 }) {
      this.sectionTitle($r('app.string.command_section_command'))
      if (p.kind === CommandPlanKind.DIRECT) {
        Text($r('app.string.command_direct_title', p.serviceName)).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
        Text($r('app.string.command_direct_note', p.serviceName)).fontSize(14).fontColor($r('app.color.screen_t2'))
        Text($r('app.string.command_zephyr_only')).fontSize(12).fontColor($r('app.color.screen_t3'))
      } else if (p.kind === CommandPlanKind.UHD) {
        Text(p.clear ? $r('app.string.command_uhd_title_all', this.who(p)) : $r('app.string.command_uhd_title_only', this.who(p)))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
        Text(this.uhdNote(p)).fontSize(14).fontColor($r('app.color.screen_t2'))
        if (p.change !== undefined) {
          Text((p.change.fromRegion + ' ' + (p.change.fromIp ?? '')).trim() + '  →  ' +
            (p.change.toRegion + ' ' + (p.change.toIp ?? '')).trim())
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
            .fontFamily('monospace')
        }
        if (!p.clear && !p.unavailable) {
          Text($r('app.string.command_uhd_auto_note')).fontSize(12).fontColor($r('app.color.screen_t3'))
        }
      } else if (p.kind === CommandPlanKind.NO_NODES) {
        Text($r('app.string.command_plan_no_nodes', p.scene !== undefined ? this.str(Labels.sceneName(p.scene)) : '',
          this.str(commandRegionName(p.regionCode))))
          .fontSize(15)
          .fontColor($r('app.color.screen_t2'))
      } else {
        Text($r('app.string.command_plan_exit_title', this.who(p), this.str(commandRegionName(p.regionCode))))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
        Text($r('app.plural.command_plan_exit_available', p.available, p.available, p.node !== undefined ? p.node.name : ''))
          .fontSize(14)
          .fontColor($r('app.color.screen_t2'))
        if (p.change !== undefined) {
          Text((p.change.fromIp ?? p.change.fromRegion) + '  →  ' + (p.change.toIp ?? p.change.toRegion))
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
            .fontFamily('monospace')
        }
        if (p.releasesPin !== undefined) {
          Text($r('app.string.command_plan_releases_pin', p.serviceName, p.releasesPin))
            .fontSize(13)
            .fontColor($r('app.color.screen_amber'))
        }
        Text(p.isSceneWord ? $r('app.string.command_plan_fallback_scene', this.str(commandRegionName(p.regionCode))) :
          $r('app.string.command_plan_fallback_pause', this.str(commandRegionName(p.regionCode)), this.who(p)))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
      }
      Button(p.applicable ? ZTerm.apply : $r('app.string.command_no_nodes_available'))
        .width('100%')
        .height(44)
        .enabled(p.applicable && !this.applying)
        .backgroundColor(p.applicable ? this.theme.accentColor() : $r('app.color.screen_s3'))
        .fontColor(Color.White)
        .onClick(() => this.apply())
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.screen_s1'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  testRuleRow() {
    Text($r('app.string.command_test_rule', this.input.trim()))
      .fontSize(16)
      .fontColor(this.theme.accentColor())
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .onClick(() => {
        this.traceHost = this.input.trim();
      })
  }

  @Builder
  nodeResults() {
    Column({ space: 2 }) {
      this.sectionTitle(ZTerm.nodes)
      ForEach(this.nodes, (n: NodeSummary) => {
        Row() {
          Text(n.name).fontSize(15).fontColor($r('app.color.screen_t1')).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (n.latencyMs !== undefined) {
            Text(n.latencyMs + ' ms').fontSize(13).fontColor($r('app.color.screen_t3'))
          }
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .accessibilityGroup(true)
        .onClick(() => this.onOpenNodes(n.name))
      }, (n: NodeSummary) => String(n.id))
      Text($r('app.string.command_see_all_nodes', Format.grouped(this.nodeTotal)))
        .fontSize(14)
        .fontColor(this.theme.accentColor())
        .padding({ top: 10, bottom: 10 })
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => this.onOpenNodes(this.parsed.region !== undefined ? this.parsed.region.code : this.input.trim()))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
