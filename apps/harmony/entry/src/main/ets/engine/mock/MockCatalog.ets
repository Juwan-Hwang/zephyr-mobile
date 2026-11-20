import { NodeSummary } from '../Model';

function gcd(a: number, b: number): number {
  let x = a;
  let y = b;
  while (y !== 0) {
    const t = x % y;
    x = y;
    y = t;
  }
  return x;
}

/** 模块级函数而非 MockCatalog 静态方法：Region 在 MockCatalog.REGIONS 的静态初始化里构造，此时外部的 MockCatalog 绑定尚未初始化（TDZ）。 */
function lcm(a: number, b: number): number {
  return a / gcd(a, b) * b;
}

/**
 * 确定性节点目录：design/prototype/pages.js 的逐位移植（contract/mock-spec.md §1–2），与 Android MockCatalog.kt 同算法。
 * 不物化任何节点：每个节点都是 (region, index) 的纯函数，1310 万节点 O(1) 内存。
 * 全部用 32 位无符号运算：`>>> 0`、Math.imul（与原型 JS 完全一致）。
 */
export class Region {
  code: string;
  name: string;
  count: number;
  cities: string[];
  baseLatency: number;
  carriers: string[];
  /** 名字里 n 的进位周期：lcm(cities, 5 * carriers) */
  namePeriod: number;

  constructor(code: string, name: string, count: number, cities: string[], baseLatency: number, carriers: string[]) {
    this.code = code;
    this.name = name;
    this.count = count;
    this.cities = cities;
    this.baseLatency = baseLatency;
    this.carriers = carriers;
    this.namePeriod = lcm(cities.length, 5 * carriers.length);
  }
}

export class MockCatalog {
  static readonly ID_STRIDE: number = 100000000;
  static readonly TAGS: string[] = ['IPLC', 'IEPL', 'BGP', '家宽', '原生'];
  static readonly PROTOCOLS: string[] = ['VLESS', 'Hy2', 'TUIC', 'SS', 'Trojan'];
  private static readonly MULT_SUFFIX: string[] = ['', '', '', '', ' ×1.5', '', '', ' ×0.5', '', ' ×2'];
  private static readonly MULT_VALUE: number[] = [0, 0, 0, 0, 1.5, 0, 0, 0.5, 0, 2];

  static readonly REGIONS: Region[] = [
    new Region('US', '美国', 3118402, ['洛杉矶', '圣何塞', '西雅图', '纽约', '达拉斯'], 152, ['CN2 GIA', 'Cogent', 'Zenlayer', 'HE']),
    new Region('JP', '日本', 2204117, ['东京', '大阪'], 58, ['NTT', 'IIJ', 'KDDI', 'SoftBank']),
    new Region('HK', '香港', 1906551, ['香港'], 34, ['HKT', 'HKBN', 'PCCW', 'CMI']),
    new Region('SG', '新加坡', 1512880, ['新加坡'], 63, ['Akari', 'SingTel', 'StarHub']),
    new Region('TW', '台湾', 1288406, ['台北', '台中'], 41, ['HiNet', 'Seednet', 'So-net']),
    new Region('KR', '韩国', 702315, ['首尔', '春川'], 69, ['KT', 'SK', 'LG U+']),
    new Region('DE', '德国', 488210, ['法兰克福', '柏林'], 204, ['Hetzner', 'DTAG']),
    new Region('GB', '英国', 455903, ['伦敦', '曼彻斯特'], 218, ['BT', 'Vultr']),
    new Region('NL', '荷兰', 301442, ['阿姆斯特丹'], 226, ['KPN', 'Leaseweb']),
    new Region('FR', '法国', 254118, ['巴黎'], 231, ['OVH', 'Orange']),
    new Region('CA', '加拿大', 239770, ['多伦多', '温哥华'], 171, ['Bell', 'Rogers']),
    new Region('AU', '澳大利亚', 214906, ['悉尼'], 139, ['Telstra', 'Optus']),
    new Region('IN', '印度', 198331, ['孟买'], 118, ['Jio', 'Airtel']),
    new Region('BR', '巴西', 126004, ['圣保罗'], 301, ['Vivo', 'Claro']),
    new Region('TR', '土耳其', 98447, ['伊斯坦布尔'], 246, ['Türk Telekom'])
  ];

  /** 13,109,802 */
  static total(): number {
    let t = 0;
    for (const g of MockCatalog.REGIONS) {
      t += g.count;
    }
    return t;
  }

  /**
   * 32 位雪崩哈希（原型 hsh），返回无符号值。j*2654435761 取低 32 位用 Math.imul：对任意 0 ≤ j < 2^32 都精确
   * （原型的 double 乘法只在 j*2654435761 < 2^53 时精确；Mock 订阅/分组按 hashCode 取 j 时会超出），与 Kotlin Long 运算一致。
   */
  static hsh(r: number, j: number): number {
    let h = (Math.imul(j, 2654435761) + r * 97) >>> 0;
    h = (h ^ (h >>> 15)) >>> 0;
    h = Math.imul(h, 2246822519) >>> 0;
    h = (h ^ (h >>> 13)) >>> 0;
    return h;
  }

  static tagOf(r: number, j: number): number {
    return (j * 7 + r) % 5;
  }

  static protOf(r: number, j: number): number {
    return MockCatalog.hsh(r + 7, j) % 5;
  }

  static carOf(r: number, j: number): number {
    return Math.floor(j / 5) % MockCatalog.REGIONS[r].carriers.length;
  }

  static cityOf(r: number, j: number): number {
    return j % MockCatalog.REGIONS[r].cities.length;
  }

  private static multIndex(r: number, j: number): number {
    return MockCatalog.hsh(r + 3, j) % 10;
  }

  static nodeName(r: number, j: number): string {
    const g = MockCatalog.REGIONS[r];
    const n = Math.floor(j / g.namePeriod) % 64 + 1;
    return `${g.cities[MockCatalog.cityOf(r, j)]} ${g.carriers[MockCatalog.carOf(r, j)]} ${MockCatalog.TAGS[MockCatalog.tagOf(r, j)]} ` +
      `${n < 10 ? '0' : ''}${n}${MockCatalog.MULT_SUFFIX[MockCatalog.multIndex(r, j)]}`;
  }

  /** 不测就显示的缓存延迟（约 27% 节点），否则 undefined。 */
  static cachedLatency(r: number, j: number): number | undefined {
    const h = MockCatalog.hsh(r, j);
    return h % 11 < 3 ? MockCatalog.REGIONS[r].baseLatency + h % 37 : undefined;
  }

  /** 按需测速结果：确定性，约 4% 超时。 */
  static testedLatency(r: number, j: number): number {
    const h = MockCatalog.hsh(r, j);
    if (h % 23 === 0) {
      return -1;
    }
    return MockCatalog.cachedLatency(r, j) ?? (MockCatalog.REGIONS[r].baseLatency + h % 37);
  }

  static idOf(r: number, j: number): number {
    return r * MockCatalog.ID_STRIDE + j;
  }

  static regionOf(id: number): number {
    return Math.floor(id / MockCatalog.ID_STRIDE);
  }

  static indexOf(id: number): number {
    return id % MockCatalog.ID_STRIDE;
  }

  static isValid(id: number): boolean {
    if (id < 0 || !Number.isInteger(id)) {
      return false;
    }
    const r = MockCatalog.regionOf(id);
    return r < MockCatalog.REGIONS.length && MockCatalog.indexOf(id) < MockCatalog.REGIONS[r].count;
  }

  static summary(r: number, j: number, latencyOverride?: number): NodeSummary {
    const g = MockCatalog.REGIONS[r];
    const m = MockCatalog.MULT_VALUE[MockCatalog.multIndex(r, j)];
    const s: NodeSummary = {
      id: MockCatalog.idOf(r, j),
      name: MockCatalog.nodeName(r, j),
      region: g.code,
      city: g.cities[MockCatalog.cityOf(r, j)],
      carrier: g.carriers[MockCatalog.carOf(r, j)],
      tag: MockCatalog.TAGS[MockCatalog.tagOf(r, j)],
      protocol: MockCatalog.PROTOCOLS[MockCatalog.protOf(r, j)],
      multiplier: m > 0 ? m : undefined,
      latencyMs: latencyOverride ?? MockCatalog.cachedLatency(r, j)
    };
    return s;
  }

  static regionIndex(code: string): number {
    const c = code.toUpperCase();
    return MockCatalog.REGIONS.findIndex((g: Region) => g.code === c);
  }

  static gcd(a: number, b: number): number {
    return gcd(a, b);
  }

  static lcm(a: number, b: number): number {
    return lcm(a, b);
  }
}
