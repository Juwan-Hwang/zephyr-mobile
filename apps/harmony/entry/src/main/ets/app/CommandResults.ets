/*
 * 指令结果 Raycast 式分组（J-3，设计规范 §9.5；对照 iOS CommandResults.swift 502c915、Android CommandResults.kt #295）：
 * 固定组序 指令 → 场景 → 节点 → 设置 → 规则测试，空组不显示；每行右侧动作标签（应用 / 打开 / 测试）；
 * 每组最多 5 行，组末「显示全部 n 项」原地展开；回车执行高亮行，否则（没有可应用的预览卡时）执行分组后第一行。
 * 实体键盘 ↓ / Tab、↑ / Shift+Tab 在可见行间移动高亮，不循环。纯逻辑，node 测试与 ohosTest 共用。
 */
import { ProxyMode } from '../engine/Model';

export enum CommandGroup {
  COMMAND = 0,
  SCENE = 1,
  NODE = 2,
  SETTINGS = 3,
  RULE_TEST = 4
}

export const COMMAND_GROUPS: CommandGroup[] = [CommandGroup.COMMAND, CommandGroup.SCENE, CommandGroup.NODE,
  CommandGroup.SETTINGS, CommandGroup.RULE_TEST];

export enum CommandVerb {
  APPLY = 'apply',
  OPEN = 'open',
  TEST = 'test'
}

/** 设置组能打开的页面（资料库与设置里的目的地；小组件页 M1-19 之后再加）。 */
export enum CommandPage {
  NODES = 'nodes',
  SUBSCRIPTIONS = 'subscriptions',
  RULES = 'rules',
  SETTINGS = 'settings',
  TRUSTED_WIFI = 'trustedWifi',
  LOCAL_PROXY = 'localProxy',
  LOGS = 'logs',
  LICENSES = 'licenses'
}

export enum CommandTargetKind {
  MODE = 'mode',
  TOGGLE = 'toggle',
  SCENE = 'scene',
  NODES = 'nodes',
  PAGE = 'page',
  RULE = 'rule'
}

/** 执行一行做什么；宿主（HomeView）把它变成具体动作。 */
export class CommandTarget {
  readonly kind: CommandTargetKind;
  /** MODE：模式；TOGGLE：'1' 连接 / '0' 断开；SCENE：场景 id；NODES：查询；PAGE：页面；RULE：输入。 */
  readonly value: string;
  /** NODES 只用来让行 key 唯一（打开的是带查询的节点库，同 iOS openNodeQuery）。 */
  readonly nodeId: number;

  constructor(kind: CommandTargetKind, value: string, nodeId?: number) {
    this.kind = kind;
    this.value = value;
    this.nodeId = nodeId ?? -1;
  }

  static mode(m: ProxyMode): CommandTarget {
    return new CommandTarget(CommandTargetKind.MODE, m);
  }

  static toggle(connect: boolean): CommandTarget {
    return new CommandTarget(CommandTargetKind.TOGGLE, connect ? '1' : '0');
  }

  static scene(id: string): CommandTarget {
    return new CommandTarget(CommandTargetKind.SCENE, id);
  }

  static nodes(query: string, nodeId: number): CommandTarget {
    return new CommandTarget(CommandTargetKind.NODES, query, nodeId);
  }

  static page(p: CommandPage): CommandTarget {
    return new CommandTarget(CommandTargetKind.PAGE, p);
  }

  static rule(input: string): CommandTarget {
    return new CommandTarget(CommandTargetKind.RULE, input);
  }

  get group(): CommandGroup {
    switch (this.kind) {
      case CommandTargetKind.MODE:
      case CommandTargetKind.TOGGLE:
        return CommandGroup.COMMAND;
      case CommandTargetKind.SCENE:
        return CommandGroup.SCENE;
      case CommandTargetKind.NODES:
        return CommandGroup.NODE;
      case CommandTargetKind.PAGE:
        return CommandGroup.SETTINGS;
      default:
        return CommandGroup.RULE_TEST;
    }
  }

  get verb(): CommandVerb {
    switch (this.kind) {
      case CommandTargetKind.MODE:
      case CommandTargetKind.TOGGLE:
        return CommandVerb.APPLY;
      case CommandTargetKind.RULE:
        return CommandVerb.TEST;
      default:
        return CommandVerb.OPEN;
    }
  }

  describe(): string {
    return this.kind + ':' + this.value + (this.nodeId >= 0 ? ':' + this.nodeId : '');
  }
}

export class CommandRow {
  readonly key: string;
  readonly title: string;
  readonly subtitle: string;
  readonly target: CommandTarget;

  constructor(key: string, title: string, subtitle: string, target: CommandTarget) {
    this.key = key;
    this.title = title;
    this.subtitle = subtitle;
    this.target = target;
  }

  get group(): CommandGroup {
    return this.target.group;
  }
}

/** 可搜索项（模式、连接 / 断开、场景、页面）。 */
export class CommandCandidate {
  readonly title: string;
  readonly subtitle: string;
  readonly target: CommandTarget;
  readonly aliases: string[];
  /** 指令类只按词首匹配，避免半个词把错误动作放到回车行。 */
  readonly prefix: boolean;

  constructor(title: string, subtitle: string, target: CommandTarget, aliases?: string[], prefix?: boolean) {
    this.title = title;
    this.subtitle = subtitle;
    this.target = target;
    this.aliases = aliases ?? [];
    this.prefix = prefix ?? false;
  }
}

export class CommandEntry {
  readonly title: string;
  readonly subtitle: string;
  readonly target: CommandTarget;

  constructor(title: string, subtitle: string, target: CommandTarget) {
    this.title = title;
    this.subtitle = subtitle;
    this.target = target;
  }
}

export class GroupedRows {
  readonly group: CommandGroup;
  readonly rows: CommandRow[];

  constructor(group: CommandGroup, rows: CommandRow[]) {
    this.group = group;
    this.rows = rows;
  }
}

export const GROUP_LIMIT: number = 5;

export class CommandResults {
  /** 不区分大小写；指令类：整词或 ≥ 2 字的词首；其余：包含。空输入不匹配。 */
  static matches(input: string, c: CommandCandidate): boolean {
    const q = input.trim().toLowerCase();
    if (q.length === 0) {
      return false;
    }
    const labels: string[] = [c.title].concat(c.aliases);
    return labels.some((x: string) => {
      const l = x.toLowerCase();
      return c.prefix ? (l === q || (q.length >= 2 && l.startsWith(q))) : l.includes(q);
    });
  }

  /** 稳定 key：组|标题|目标；重复的加 #n。 */
  static rows(entries: CommandEntry[]): CommandRow[] {
    const seen = new Map<string, number>();
    return entries.map((e: CommandEntry) => {
      const base = e.target.group + '|' + e.title + '|' + e.target.describe();
      const n = seen.get(base) ?? 0;
      seen.set(base, n + 1);
      return new CommandRow(n === 0 ? base : base + '#' + n, e.title, e.subtitle, e.target);
    });
  }

  static groups(rows: CommandRow[]): GroupedRows[] {
    const out: GroupedRows[] = [];
    for (const g of COMMAND_GROUPS) {
      const rs = rows.filter((r: CommandRow) => r.group === g);
      if (rs.length > 0) {
        out.push(new GroupedRows(g, rs));
      }
    }
    return out;
  }

  static shown(g: GroupedRows, expanded: CommandGroup[]): CommandRow[] {
    return expanded.includes(g.group) || g.rows.length <= GROUP_LIMIT ? g.rows : g.rows.slice(0, GROUP_LIMIT);
  }

  static visibleRows(groups: GroupedRows[], expanded: CommandGroup[]): CommandRow[] {
    const out: CommandRow[] = [];
    groups.forEach((g: GroupedRows) => {
      CommandResults.shown(g, expanded).forEach((r: CommandRow) => out.push(r));
    });
    return out;
  }

  static firstRow(groups: GroupedRows[]): CommandRow | undefined {
    return groups.length > 0 && groups[0].rows.length > 0 ? groups[0].rows[0] : undefined;
  }

  /**
   * 一步之后的高亮（↑ = −1，↓ / Tab = +1），两端停住不循环（iOS moveHighlight）。
   * 无高亮 + 有可应用预览：↓ 到第一行；无高亮无预览：第一行已是默认，↓ 到第二行；有预览时从第一行 ↑ 回到无高亮。
   */
  static moveHighlight(current: string | undefined, rows: string[], step: number, hasPrimary: boolean): string | undefined {
    if (rows.length === 0 || step === 0) {
      return current;
    }
    const floor = hasPrimary ? -1 : 0;
    const idx = current !== undefined ? rows.indexOf(current) : -1;
    const at = idx >= 0 ? idx : floor;
    const next = Math.min(Math.max(at + (step > 0 ? 1 : -1), floor), rows.length - 1);
    return next < 0 ? undefined : rows[next];
  }

  /** 回车执行的行：高亮行；否则（没有预览卡时）第一行；undefined = 应用预览。 */
  static enterRow(groups: GroupedRows[], expanded: CommandGroup[], highlighted: string | undefined,
    hasPrimary: boolean): CommandRow | undefined {
    if (highlighted !== undefined) {
      const r = CommandResults.visibleRows(groups, expanded).find((x: CommandRow) => x.key === highlighted);
      if (r !== undefined) {
        return r;
      }
    }
    return hasPrimary ? undefined : CommandResults.firstRow(groups);
  }

  /** 读屏 / 加粗用的默认行 key。 */
  static defaultKey(groups: GroupedRows[], highlighted: string | undefined, hasPrimary: boolean): string | undefined {
    if (highlighted !== undefined) {
      return highlighted;
    }
    if (hasPrimary) {
      return undefined;
    }
    const f = CommandResults.firstRow(groups);
    return f !== undefined ? f.key : undefined;
  }
}
