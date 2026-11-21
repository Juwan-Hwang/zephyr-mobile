import { LayerKind, RuleLayer } from '../Model';

/** 一次命中：layer = 层序号，ruleNo = 原型第 4 列，policy = 原型策略码（AI / V / O / DIRECT / REJECT）。 */
export class RuleHit {
  layer: number;
  rule: string;
  ruleNo: number;
  policy: string;

  constructor(layer: number, rule: string, ruleNo: number, policy: string) {
    this.layer = layer;
    this.rule = rule;
    this.ruleNo = ruleNo;
    this.policy = policy;
  }
}

type RuleText = (q: string) => string;

class RuleRow {
  layer: number;
  re: RegExp;
  rule: RuleText;
  no: number;
  policy: string;

  constructor(layer: number, re: RegExp, rule: RuleText, no: number, policy: string) {
    this.layer = layer;
    this.re = re;
    this.rule = rule;
    this.no = no;
    this.policy = policy;
  }
}

function layer(index: number, kind: LayerKind, name: string, count: number, note: string): RuleLayer {
  const l: RuleLayer = { index: index, kind: kind, name: name, count: count, note: note };
  return l;
}

/**
 * 规则层与原型 `matchRule`（contract/mock-spec.md §4），逐行对照 Android MockRules.kt。
 * 校验样本：contract/fixtures/mock-v0.json `rules`。
 */
export class MockRules {
  static readonly LAYERS: RuleLayer[] = [
    layer(0, LayerKind.OVERRIDE, 'Zephyr 覆写', 14, '在订阅之上'),
    layer(1, LayerKind.SUBSCRIPTION, 'Nebula Cloud', 1284, '订阅规则'),
    layer(2, LayerKind.DOMAIN, 'OpenAI', 312, '规则集 · 每天更新'),
    layer(3, LayerKind.DOMAIN, '广告与跟踪', 61204113, '规则集 · 每天更新'),
    layer(4, LayerKind.DOMAIN, '威胁情报', 33481790, '规则集 · 每小时更新'),
    layer(5, LayerKind.DOMAIN, 'geosite:cn', 8912004, '规则集 · 每周更新'),
    layer(6, LayerKind.IP, 'geoip:cn', 7214, '规则集 · 每周更新')
  ];
  static readonly DISK_BYTES: number = 1900000000;

  private static readonly IPV4: RegExp = new RegExp('^\\d+\\.\\d+\\.\\d+\\.\\d+$');
  private static readonly IPV6: RegExp = new RegExp('^[0-9a-f:]+$');
  private static readonly KW: RegExp = new RegExp('doubleclick|adservice|ads?|tracker|analytics');

  private static lastTwo(q: string): string {
    return q.split('.').slice(-2).join('.');
  }

  private static readonly TABLE: RuleRow[] = [
    new RuleRow(0, new RegExp('(^|\\.)github\\.com$'), (q: string) => 'DOMAIN-SUFFIX,github.com', 2, 'DIRECT'),
    new RuleRow(1, new RegExp('(^|\\.)netflix\\.com$|(^|\\.)nflxvideo\\.net$'), (q: string) => 'DOMAIN-SUFFIX,netflix.com', 318, 'V'),
    new RuleRow(2, new RegExp('(^|\\.)openai\\.com$|(^|\\.)chatgpt\\.com$|(^|\\.)claude\\.ai$|(^|\\.)anthropic\\.com$'),
      (q: string) => 'DOMAIN-SUFFIX,' + MockRules.lastTwo(q), 41, 'AI'),
    new RuleRow(3, new RegExp('doubleclick|adservice|(^|\\.)ads?\\.|tracker|analytics'), (q: string) => {
      const m = MockRules.KW.exec(q);
      return 'DOMAIN-KEYWORD,' + (m !== null ? m[0] : 'ad');
    }, 18204451, 'REJECT'),
    new RuleRow(4, new RegExp('malware|phish'), (q: string) => 'DOMAIN,' + q, 2201833, 'REJECT'),
    new RuleRow(5, new RegExp('(^|\\.)(baidu|qq|taobao|bilibili|weibo|jd)\\.com$|\\.cn$'),
      (q: string) => 'DOMAIN-SUFFIX,' + MockRules.lastTwo(q), 1120458, 'DIRECT'),
    new RuleRow(6,
      new RegExp('^(1\\.0\\.|36\\.|58\\.|101\\.|110\\.|111\\.|112\\.|113\\.|114\\.|115\\.|116\\.|117\\.|118\\.|119\\.|120\\.|121\\.|122\\.|123\\.|124\\.|125\\.)'),
      (q: string) => 'IP-CIDR,' + q.split('.').slice(0, 2).join('.') + '.0.0/16', 3302, 'DIRECT')
  ];

  /** 103,606,731 */
  static total(): number {
    let t = 0;
    for (const l of MockRules.LAYERS) {
      t += l.count;
    }
    return t;
  }

  static normalise(input: string): string {
    return input.trim().toLowerCase();
  }

  static isIp(q: string): boolean {
    return MockRules.IPV4.test(q) || (q.includes(':') && MockRules.IPV6.test(q));
  }

  /** 按层序第一条命中；域名不进 IP 层，IPv4 只进 IP 层。 */
  static match(q: string): RuleHit | undefined {
    const ip = MockRules.IPV4.test(q);
    for (const r of MockRules.TABLE) {
      if (ip !== (r.layer === 6)) {
        continue;
      }
      if (r.re.test(q)) {
        return new RuleHit(r.layer, r.rule(q), r.no, r.policy);
      }
    }
    return undefined;
  }

  /** 原型策略码 → 场景 id。 */
  static sceneIdFor(policy: string): string | undefined {
    switch (policy) {
      case 'AI':
        return 'ai';
      case 'V':
        return 'video';
      case 'O':
        return 'other';
      default:
        return undefined;
    }
  }
}
