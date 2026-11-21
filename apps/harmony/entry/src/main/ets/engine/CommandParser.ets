/*
 * 指令解析（契约 §15.b / §17：原型 parse()，index.html ~1022）：在自由文本里找服务、地区、操作。
 * 逐行移植 Android CommandParser.kt（iOS CommandTokenizer 同源），多语言别名用契约 U25 的共用表。
 * 纯同步：每次按键都可重算下划线（原型 .tk.s / .r / .a）。下标为 UTF-16（与 JS / ArkTS 字符串一致）。
 * 以 contract/fixtures/command-parse-v1.json 逐条校验（ohosTest CommandParse.test + node 测试）。
 */
import { SceneKind } from './Model';
import { MockApp, MockApps } from './mock/MockFixtures';

export enum CommandTok {
  SERVICE = 'service',
  REGION = 'region',
  ACTION = 'action'
}

export enum CommandAct {
  DIRECT = '直连',
  UHD = '4K'
}

export class CommandSpan {
  start: number;
  length: number;
  kind: CommandTok;

  constructor(start: number, length: number, kind: CommandTok) {
    this.start = start;
    this.length = length;
    this.kind = kind;
  }
}

export class CommandRegion {
  /** 规范名（中文，原型 RGN 的键）。 */
  name: string;
  code: string;

  constructor(name: string, code: string) {
    this.name = name;
    this.code = code;
  }
}

/** 用户点名的服务：内置应用、场景词（"视频"），或带域名的"其他"服务。 */
export class CommandService {
  name: string;
  kind: SceneKind;
  appId: string | undefined;
  host: string | undefined;

  constructor(name: string, kind: SceneKind, appId?: string, host?: string) {
    this.name = name;
    this.kind = kind;
    this.appId = appId;
    this.host = host;
  }

  get isSceneWord(): boolean {
    return this.appId === undefined && this.host === undefined;
  }

  /** 契约 §15.b 的 scope：AI | 视频 | 其他。 */
  get scope(): string {
    if (this.kind === SceneKind.AI) {
      return 'AI';
    }
    if (this.kind === SceneKind.VIDEO) {
      return '视频';
    }
    return '其他';
  }
}

export class ParsedCommand {
  service: CommandService | undefined;
  region: CommandRegion | undefined;
  act: CommandAct | undefined;
  /** 按 start 升序。 */
  spans: CommandSpan[];

  constructor(service: CommandService | undefined, region: CommandRegion | undefined, act: CommandAct | undefined,
    spans: CommandSpan[]) {
    this.service = service;
    this.region = region;
    this.act = act;
    this.spans = spans;
  }

  /** 有服务或操作才出解析卡片（原型）。 */
  get hasChips(): boolean {
    return this.service !== undefined || this.act !== undefined;
  }
}

class Alias {
  name: string;
  key: string;
  words: string[];

  constructor(name: string, key: string, words: string[]) {
    this.name = name;
    this.key = key;
    this.words = words;
  }
}

class ActAlias {
  act: CommandAct;
  words: string[];

  constructor(act: CommandAct, words: string[]) {
    this.act = act;
    this.words = words;
  }
}

export class CommandParser {
  /** 原型 RGN + 节点库其余地区；ar / fa / ur 别名见契约 U25 表（与 Android 同表）。 */
  private static readonly REGIONS: Alias[] = [
    new Alias('日本', 'JP', ['日本', '东京', '大阪', 'jp', 'japan', 'tokyo', 'اليابان', 'طوكيو', 'ژاپن', 'توکیو', 'جاپان', 'ٹوکیو']),
    new Alias('美国', 'US', ['美国', '洛杉矶', 'us', 'usa', 'الولايات المتحدة', 'أمريكا', 'آمریکا', 'امریکا', 'امریکہ']),
    new Alias('香港', 'HK', ['香港', 'hk', 'هونغ كونغ', 'هنگ کنگ', 'ہانگ کانگ']),
    new Alias('新加坡', 'SG', ['新加坡', '狮城', 'sg', 'سنغافورة', 'سنگاپور']),
    new Alias('台湾', 'TW', ['台湾', '台北', 'tw', 'تايوان', 'تایوان', 'تائیوان']),
    new Alias('英国', 'GB', ['英国', '伦敦', 'uk', 'gb', 'المملكة المتحدة', 'بريطانيا', 'بریتانیا', 'انگلیس', 'برطانیہ']),
    new Alias('韩国', 'KR', ['韩国', '首尔', 'kr', 'كوريا', 'کره', 'کوریا']),
    new Alias('德国', 'DE', ['德国', '法兰克福', 'de', 'ألمانيا', 'آلمان', 'جرمنی'])
  ];

  /** 原型 SVC 中"其他"场景的服务：可按域名直连。 */
  private static readonly OTHER: Alias[] = [
    new Alias('GitHub', 'github.com', ['github']),
    new Alias('Telegram', 'telegram.org', ['telegram', '电报', 'tg'])
  ];

  private static readonly ACTS: ActAlias[] = [
    new ActAlias(CommandAct.DIRECT, ['直连', '不走代理', 'direct', 'مباشر', 'مستقیم', 'براہ راست']),
    new ActAlias(CommandAct.UHD, ['4k'])
  ];

  /** 场景词"视频"（原型正则 视频|流媒体 + U25 别名），取最左匹配，同位置按表序。 */
  private static readonly VIDEO_WORDS: string[] = ['视频', '流媒体', 'الفيديو', 'فيديو', 'ویدیو', 'ویڈیو'];

  static parse(q: string): ParsedCommand {
    const lo = q.toLowerCase();
    const spans: CommandSpan[] = [];
    let svc: CommandService | undefined = undefined;
    for (const a of MockApps.ALL) {
      const app: MockApp = a;
      for (const k of app.aliases) {
        const i = lo.indexOf(k);
        if (i >= 0) {
          svc = new CommandService(app.name, app.kind, app.id, undefined);
          spans.push(new CommandSpan(i, k.length, CommandTok.SERVICE));
          break;
        }
      }
      if (svc !== undefined) {
        break;
      }
    }
    if (svc === undefined) {
      for (const o of CommandParser.OTHER) {
        for (const k of o.words) {
          const i = CommandParser.indexOfWord(lo, k);
          if (i >= 0) {
            svc = new CommandService(o.name, SceneKind.OTHER, undefined, o.key);
            spans.push(new CommandSpan(i, k.length, CommandTok.SERVICE));
            break;
          }
        }
        if (svc !== undefined) {
          break;
        }
      }
    }
    let rg: CommandRegion | undefined = undefined;
    for (const r of CommandParser.REGIONS) {
      for (const k of r.words) {
        const i = CommandParser.indexOfWord(lo, k);
        if (i >= 0 && !CommandParser.overlaps(spans, i, k.length)) {
          rg = new CommandRegion(r.name, r.key);
          spans.push(new CommandSpan(i, k.length, CommandTok.REGION));
          break;
        }
      }
      if (rg !== undefined) {
        break;
      }
    }
    let act: CommandAct | undefined = undefined;
    for (const a of CommandParser.ACTS) {
      for (const k of a.words) {
        const i = lo.indexOf(k);
        if (i >= 0) {
          act = a.act;
          spans.push(new CommandSpan(i, k.length, CommandTok.ACTION));
          break;
        }
      }
      if (act !== undefined) {
        break;
      }
    }
    if (svc === undefined) {
      let best = -1;
      let bestLen = 0;
      for (const w of CommandParser.VIDEO_WORDS) {
        const i = q.indexOf(w);
        if (i >= 0 && (best < 0 || i < best)) {
          best = i;
          bestLen = w.length;
        }
      }
      if (best >= 0) {
        svc = new CommandService('视频', SceneKind.VIDEO, undefined, undefined);
        spans.push(new CommandSpan(best, bestLen, CommandTok.SERVICE));
      }
    }
    spans.sort((x: CommandSpan, y: CommandSpan) => x.start - y.start);
    return new ParsedCommand(svc, rg, act, spans);
  }

  /** 原型规则：≤2 个拉丁字母的关键字不得嵌在单词里（"status" 里的 "us"）。 */
  private static indexOfWord(lo: string, k: string): number {
    const short = k.length <= 2 && CommandParser.allLatin(k);
    let from = 0;
    while (true) {
      const i = lo.indexOf(k, from);
      if (i < 0) {
        return -1;
      }
      if (!short) {
        return i;
      }
      const before = i > 0 ? lo.charAt(i - 1) : '';
      const after = i + k.length < lo.length ? lo.charAt(i + k.length) : '';
      if (!CommandParser.isLatin(before) && !CommandParser.isLatin(after)) {
        return i;
      }
      from = i + 1;
    }
  }

  private static isLatin(c: string): boolean {
    return c.length === 1 && c >= 'a' && c <= 'z';
  }

  private static allLatin(k: string): boolean {
    for (let j = 0; j < k.length; j++) {
      if (!CommandParser.isLatin(k.charAt(j))) {
        return false;
      }
    }
    return true;
  }

  private static overlaps(spans: CommandSpan[], i: number, len: number): boolean {
    return spans.some((s: CommandSpan) => i < s.start + s.length && s.start < i + len);
  }
}
