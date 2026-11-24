import { LengthMetrics } from '@kit.ArkUI';
/*
 * “搜索或输入指令”面板（原型 cmdv，index.html 879 / 1020–1061；对照 Android CommandOverlay、iOS CommandView；契约 §16.d）。
 * 首页底栏指令栏点开（bindSheet）。
 * - 空输入：“建议”示例短语，点按只填入输入框并重新解析，不直接执行（U24）。
 * - 有输入：token 下划线预览（服务蓝 / 地区绿 / 操作琥珀）、解析卡片（服务 / 范围 / 地区 / 操作）、
 *   一张预览卡（含出口 IP 行），点“应用”（或回车）才执行：先关面板再执行（同 Android），首页出撤销吐司（§16.e⑥）。
 *   “视频只用 4K 节点”出 4K 卡（§15.h，同 Android CommandPlan.Uhd）：N 个中 M 个支持 4K / 当前节点保持 / 将使用 X /
 *   尚未测速 / 没有支持 4K 的节点（按钮禁用）/ 已过滤时“使用全部节点”。
 * - 只有地区或普通文本：节点结果（最快前 5 个 + 查看全部）；像域名 / IP：“X 走哪里？”→ 面板内原地显示连接轨迹
 *   （TraceBody，规则 → 场景 → 节点 → 出口 + 覆写；没有连接记录时退回规则测试）。Android / iOS 此行去规则页测试，
 *   鸿蒙按 #241 指派改为轨迹（规则页仍在资料库）。
 * - J-3（§9.5，同 iOS CommandResults / Android #295）：预览卡之下结果按 指令 → 场景 → 节点 → 设置 → 规则测试 分组，
 *   行右侧动作标签（应用 / 打开 / 测试），每组 5 行 +「显示全部 n 项」；回车：有可应用预览卡时应用，否则执行第一行；
 *   实体键盘 ↓ / Tab、↑ / Shift+Tab 移动高亮（不循环），回车执行高亮行；默认行动作标签加粗、读屏读「按回车执行」。
 */
import { AppServices } from '../app/AppServices';
import { CommandApplier, CommandApplyTexts } from '../app/CommandApplier';
import { CommandPlan, CommandPlanKind, CommandPlanner } from '../app/CommandPlanner';
import { Haptics, HapticKind } from '../app/Haptics';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { CommandAct, CommandParser, CommandSpan, CommandTok, ParsedCommand } from '../engine/CommandParser';
import { NodeQueryResult, NodeSummary, ProxyMode, Scene } from '../engine/Model';
import { KeyCode } from '@kit.InputKit';
import { CommandCandidate, CommandEntry, CommandGroup, CommandPage, CommandResults, CommandRow, CommandTarget,
  CommandTargetKind, CommandVerb, GroupedRows } from '../app/CommandResults';
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
  /** J-3 结果行：切换模式 / 连接·断开 / 打开场景 sheet / 打开页面（宿主先收起面板）。 */
  @Event onSetMode: (m: ProxyMode) => void = (m: ProxyMode) => {};
  @Event onToggle: (connect: boolean) => void = (connect: boolean) => {};
  @Event onOpenScene: (id: string) => void = (id: string) => {};
  @Event onOpenPage: (p: CommandPage) => void = (p: CommandPage) => {};
  /** 连接中 / 已连接时候选是「断开连接」，否则「连接」。 */
  @Param connected: boolean = false;
  @Param scenes: Scene[] = [];

  @Local input: string = '';
  @Local parsed: ParsedCommand = CommandParser.parse('');
  @Local plan: CommandPlan | undefined = undefined;
  @Local nodes: NodeSummary[] = [];
  @Local nodeTotal: number = 0;
  /** 节点行所属的查询（地区代码或输入），节点行与「查看全部」都打开带这个查询的节点库。 */
  @Local nodeQuery: string = '';
  @Local applying: boolean = false;
  /** “X 走哪里？”点开后在面板内原地显示的连接轨迹（M1-8 最小版）；'' = 不显示。 */
  @Local traceHost: string = '';
  @Local expanded: CommandGroup[] = [];
  @Local highlighted: string | undefined = undefined;
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
    this.expanded = [];
    this.highlighted = undefined;
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
      this.nodeQuery = q;
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

  /** §9.5 组 ①②④ 的可搜索项：模式、连接 / 断开（只按词首），场景与页面（包含即可）。 */
  private candidates(): CommandCandidate[] {
    const out: CommandCandidate[] = [];
    out.push(new CommandCandidate(this.str(ZTerm.modeRule), this.str($r('app.string.common_mode_rule_hint')),
      CommandTarget.mode(ProxyMode.RULE), ['规则模式', 'rule'], true));
    out.push(new CommandCandidate(this.str(ZTerm.modeGlobal), this.str($r('app.string.common_mode_global_hint')),
      CommandTarget.mode(ProxyMode.GLOBAL), ['全局模式', 'global'], true));
    out.push(new CommandCandidate(this.str(ZTerm.modeDirect), this.str($r('app.string.common_mode_direct_hint')),
      CommandTarget.mode(ProxyMode.DIRECT), ['直连模式', 'direct'], true));
    out.push(this.connected ?
      new CommandCandidate(this.str(ZTerm.disconnect), '', CommandTarget.toggle(false), ['断开', 'disconnect'], true) :
      new CommandCandidate(this.str($r('app.string.common_connect')), '', CommandTarget.toggle(true), ['连接', 'connect'], true));
    this.scenes.forEach((sc: Scene) => {
      out.push(new CommandCandidate(this.str(Labels.sceneName(sc)), sc.selected.name, CommandTarget.scene(sc.id)));
    });
    const pages: [ResourceStr, CommandPage][] = [
      [ZTerm.nodes, CommandPage.NODES], [ZTerm.subscriptions, CommandPage.SUBSCRIPTIONS], [ZTerm.rules, CommandPage.RULES],
      [ZTerm.settings, CommandPage.SETTINGS], [$r('app.string.settings_trusted_wifi'), CommandPage.TRUSTED_WIFI],
      [ZTerm.localProxyPort, CommandPage.LOCAL_PROXY], [ZTerm.logs, CommandPage.LOGS],
      [$r('app.string.settings_licenses'), CommandPage.LICENSES]];
    pages.forEach((pg: [ResourceStr, CommandPage]) => {
      out.push(new CommandCandidate(this.str(pg[0]), '', CommandTarget.page(pg[1])));
    });
    return out;
  }

  private resultGroups(): GroupedRows[] {
    const q = this.input.trim();
    const entries: CommandEntry[] = [];
    if (q.length > 0) {
      this.candidates().filter((c: CommandCandidate) => CommandResults.matches(q, c)).forEach((c: CommandCandidate) => {
        entries.push(new CommandEntry(c.title, c.subtitle, c.target));
      });
    }
    this.nodes.forEach((n: NodeSummary) => {
      const sub: string[] = [n.region];
      if (n.latencyMs !== undefined && n.latencyMs >= 0) {
        sub.push(n.latencyMs + ' ms');
      }
      entries.push(new CommandEntry(n.name, sub.join(' · '), CommandTarget.nodes(this.nodeQuery, n.id)));
    });
    if (CommandPlanner.looksLikeHost(q)) {
      entries.push(new CommandEntry(this.str($r('app.string.command_test_rule', q)), '', CommandTarget.rule(q)));
    }
    return CommandResults.groups(CommandResults.rows(entries));
  }

  private hasPrimary(): boolean {
    return this.plan !== undefined && this.plan.applicable;
  }

  private run(row: CommandRow): void {
    const t = row.target;
    switch (t.kind) {
      case CommandTargetKind.MODE:
        this.onSetMode(t.value as ProxyMode);
        break;
      case CommandTargetKind.TOGGLE:
        this.onToggle(t.value === '1');
        break;
      case CommandTargetKind.SCENE:
        this.onOpenScene(t.value);
        break;
      case CommandTargetKind.NODES:
        // 同 iOS openNodeQuery：打开带查询的节点库（nodeId 只让 key 唯一）。
        this.onOpenNodes(t.value);
        break;
      case CommandTargetKind.PAGE:
        this.onOpenPage(t.value as CommandPage);
        break;
      default:
        // 鸿蒙按 #241：规则测试在面板内原地显示连接轨迹。
        this.traceHost = t.value;
        break;
    }
  }

  /** 回车：高亮行 → 可应用的预览 → 第一行。 */
  private submit(): void {
    const row = CommandResults.enterRow(this.resultGroups(), this.expanded, this.highlighted, this.hasPrimary());
    if (row !== undefined) {
      this.run(row);
    } else {
      this.apply();
    }
  }

  /** 实体键盘（§9.5）：↓ / Tab 下移、↑ / Shift+Tab 上移；输入法组字中的按键不会到这里。 */
  private onKey(e: KeyEvent): boolean {
    if (e.type !== KeyType.Down || this.input.trim().length === 0) {
      return false;
    }
    let step = 0;
    if (e.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      step = 1;
    } else if (e.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      step = -1;
    } else if (e.keyCode === KeyCode.KEYCODE_TAB) {
      const shift = e.getModifierKeyState !== undefined && e.getModifierKeyState(['Shift']);
      step = shift ? -1 : 1;
    } else {
      return false;
    }
    const keys = CommandResults.visibleRows(this.resultGroups(), this.expanded).map((r: CommandRow) => r.key);
    this.highlighted = CommandResults.moveHighlight(this.highlighted, keys, step, this.hasPrimary());
    return true;
  }

  private groupTitle(g: CommandGroup): ResourceStr {
    switch (g) {
      case CommandGroup.COMMAND:
        return $r('app.string.command_section_command');
      case CommandGroup.SCENE:
        return ZTerm.scenes;
      case CommandGroup.NODE:
        return ZTerm.nodes;
      case CommandGroup.SETTINGS:
        return ZTerm.settings;
      default:
        return $r('app.string.command_group_rule_test');
    }
  }

  private verbLabel(v: CommandVerb): ResourceStr {
    if (v === CommandVerb.APPLY) {
      return ZTerm.apply;
    }
    return v === CommandVerb.TEST ? $r('app.string.command_action_test') : $r('app.string.command_action_open');
  }

  private rowSymbol(k: CommandTargetKind): Resource {
    switch (k) {
      case CommandTargetKind.MODE:
        return $r('sys.symbol.map');
      case CommandTargetKind.TOGGLE:
        return $r('sys.symbol.bolt');
      case CommandTargetKind.SCENE:
        return $r('sys.symbol.arrow_right');
      case CommandTargetKind.NODES:
        return $r('sys.symbol.magnifyingglass');
      case CommandTargetKind.PAGE:
        return $r('sys.symbol.square_grid_2x2');
      default:
        return $r('sys.symbol.checkmark');
    }
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

  /** 同 Android：先关面板再执行（app/CommandApplier），结果吐司出在首页上。 */
  private apply(): void {
    const p = this.plan;
    if (p === undefined || !p.applicable || this.applying) {
      return;
    }
    this.applying = true;
    const who = this.who(p);
    const texts: CommandApplyTexts = {
      success: this.toastText(p, who),
      failed: this.str($r('app.string.home_apply_failed'), who)
    };
    CommandApplier.run(this.planner, p, AppServices.get().toasts, texts, () => this.onDone(), () => {
      Haptics.play(HapticKind.SUCCESS);
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
          .onSubmit(() => this.submit())
          .onKeyEvent((e: KeyEvent) => this.onKey(e))

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
          this.resultList(this.resultGroups())
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
        .margin({ end: LengthMetrics.vp(8), bottom: LengthMetrics.vp(8) })
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
            .fontColor($r('app.color.screen_amber_text'))
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
    .borderRadius(24)
    .backgroundColor($r('app.color.screen_s2'))
    .border({ width: 1, color: $r('app.color.screen_hl') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultList(groups: GroupedRows[]) {
    Column() {
      ForEach(groups, (g: GroupedRows) => {
        this.resultGroup(g, CommandResults.defaultKey(groups, this.highlighted, this.hasPrimary()))
      }, (g: GroupedRows) => g.group + '|' + g.rows.map((r: CommandRow) => r.key).join(';'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultGroup(g: GroupedRows, defaultKey: string | undefined) {
    Column() {
      Text(this.groupTitle(g.group))
        .fontSize(13)
        .fontColor($r('app.color.screen_t3'))
        .padding({ start: LengthMetrics.vp(14), top: LengthMetrics.vp(16), bottom: LengthMetrics.vp(8) })
      Column() {
        ForEach(CommandResults.shown(g, this.expanded), (row: CommandRow, i: number) => {
          if (i > 0) {
            Divider().strokeWidth(1).color($r('app.color.screen_hl')).margin({ start: LengthMetrics.vp(48) })
          }
          this.resultRow(row, row.key === defaultKey, row.key === this.highlighted)
        }, (row: CommandRow) => row.key + (row.key === defaultKey ? '*' : '') + (row.key === this.highlighted ? '^' : ''))
        if (CommandResults.shown(g, this.expanded).length < g.rows.length) {
          Divider().strokeWidth(1).color($r('app.color.screen_hl'))
          this.footer($r('app.string.command_show_all', String(g.rows.length)), () => {
            this.expanded = this.expanded.concat([g.group]);
          })
        } else if (g.group === CommandGroup.NODE && this.nodeTotal > g.rows.length) {
          Divider().strokeWidth(1).color($r('app.color.screen_hl'))
          this.footer($r('app.string.command_see_all_nodes', Format.grouped(this.nodeTotal)), () => {
            this.onOpenNodes(this.nodeQuery);
          })
        }
      }
      .width('100%')
      .borderRadius(24)
      .backgroundColor($r('app.color.screen_s2'))
      .border({ width: 1, color: $r('app.color.screen_hl') })
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  footer(label: ResourceStr, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(this.theme.accentColor())
      .width('100%')
      .padding({ start: LengthMetrics.vp(18), end: LengthMetrics.vp(18), top: LengthMetrics.vp(14),
        bottom: LengthMetrics.vp(14) })
      .accessibilityRole(AccessibilityRoleType.BUTTON)
      .onClick(action)
  }

  /** 一行：图标 t2、标题 t1、副标题 t3，右侧动作标签强调色无底色；默认行标签加粗，高亮行 pressed 底色。 */
  @Builder
  resultRow(row: CommandRow, isDefault: boolean, isHighlighted: boolean) {
    Row({ space: 14 }) {
      SymbolGlyph(this.rowSymbol(row.target.kind))
        .fontSize(18)
        .fontColor([$r('app.color.screen_t2')])
        .accessibilityLevel('no')
      Column({ space: 2 }) {
        Text(row.title)
          .fontSize(16)
          .fontColor($r('app.color.screen_t1'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (row.subtitle.length > 0) {
          Text(row.subtitle)
            .fontSize(12)
            .fontColor($r('app.color.screen_t3'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.verbLabel(row.target.verb))
        .fontSize(13)
        .fontWeight(isDefault ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.theme.accentColor())
        .maxLines(1)
    }
    .width('100%')
    .padding({ start: LengthMetrics.vp(16), end: LengthMetrics.vp(16), top: LengthMetrics.vp(12),
      bottom: LengthMetrics.vp(12) })
    .backgroundColor(isHighlighted ? $r('app.color.screen_pressed') : Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .accessibilityDescription(isDefault ? getContext(this).resourceManager.getStringSync($r('app.string.command_enter_hint').id) : '')
    .accessibilitySelected(isHighlighted)
    .onClick(() => this.run(row))
  }
}
