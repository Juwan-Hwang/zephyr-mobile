import { RegionSection } from '../Model';
import { MockCatalog, Region } from './MockCatalog';

/** 一个命中分区：周期 period 内满足条件的余数 residues，计数与随机访问都是 O(|S|) / O(1)。 */
export class QueryGroup {
  region: number;
  count: number;
  residues: number[];
  period: number;
  rowOffset: number;
  nodeOffset: number;

  constructor(region: number, count: number, residues: number[], period: number, rowOffset: number, nodeOffset: number) {
    this.region = region;
    this.count = count;
    this.residues = residues;
    this.period = period;
    this.rowOffset = rowOffset;
    this.nodeOffset = nodeOffset;
  }
}

/**
 * 只走索引的节点查询：原型 `buildModel` 的移植（contract/mock-spec.md §3），与 Android NodeQuery.kt 同算法。
 * 绝不扫全表。
 */
export class NodeQuery {
  query: string;
  groups: QueryGroup[];
  highlights: string[];
  total: number;

  private constructor(query: string, groups: QueryGroup[], highlights: string[]) {
    this.query = query;
    this.groups = groups;
    this.highlights = highlights;
    let t = 0;
    for (const g of groups) {
      t += g.count;
    }
    this.total = t;
  }

  sections(): RegionSection[] {
    return this.groups.map((it: QueryGroup) => {
      const g = MockCatalog.REGIONS[it.region];
      const s: RegionSection = { region: g.code, name: g.name, count: it.count, rowOffset: it.rowOffset };
      return s;
    });
  }

  /** 第 ordinal 个命中节点（0 起，不含头行）所在分组。 */
  groupForOrdinal(ordinal: number): number {
    let lo = 0;
    let hi = this.groups.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >>> 1;
      if (this.groups[mid].nodeOffset <= ordinal) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /** 分组内第 k 个节点在地区里的序号 j。 */
  indexInRegion(group: QueryGroup, k: number): number {
    const s = group.residues.length;
    return Math.floor(k / s) * group.period + group.residues[k % s];
  }

  static build(raw: string): NodeQuery {
    const regions = MockCatalog.REGIONS;
    const typing = new RegExp('^[a-z0-9+-]{1,3}$');
    const ws = new RegExp('\\s+');
    const tokens = raw.trim().toLowerCase().split(ws).filter((t: string) => t.length > 0);
    let regs: Set<number> | undefined = undefined;
    const cityTok = new Map<number, number>();
    const car = new Map<number, number>();
    let tag = -1;
    let ok = true;
    const hl: string[] = [];

    for (let ti = 0; ti < tokens.length; ti++) {
      const tk = tokens[ti];
      const last = ti === tokens.length - 1;
      const s = new Set<number>();
      // a. 地区
      regions.forEach((g: Region, ri: number) => {
        if (g.code.toLowerCase() === tk || g.name.includes(tk) || tk.includes(g.name)) {
          s.add(ri);
        }
      });
      if (s.size > 0) {
        regs = NodeQuery.meet(regs, s);
        hl.push(tk);
        continue;
      }
      // b. 城市
      regions.forEach((g: Region, ri: number) => {
        g.cities.forEach((c: string, ci: number) => {
          if (c.includes(tk) || tk.includes(c)) {
            s.add(ri);
            cityTok.set(ri, ci);
            hl.push(c);
          }
        });
      });
      if (s.size > 0) {
        regs = NodeQuery.meet(regs, s);
        continue;
      }
      // c. 运营商
      regions.forEach((g: Region, ri: number) => {
        const ci = g.carriers.findIndex((x: string) => {
          const l = x.toLowerCase();
          return l === tk || l.replace(new RegExp('\\s+', 'g'), '') === tk || l.split(ws).includes(tk) ||
            (tk.length >= 2 && l.startsWith(tk));
        });
        if (ci >= 0) {
          s.add(ri);
          car.set(ri, ci);
          hl.push(g.carriers[ci]);
        }
      });
      if (s.size > 0) {
        regs = NodeQuery.meet(regs, s);
        continue;
      }
      // d. 标签
      const tIdx = MockCatalog.TAGS.findIndex((x: string) => {
        const l = x.toLowerCase();
        return l === tk || (tk.length >= 2 && l.startsWith(tk));
      });
      if (tIdx >= 0) {
        tag = tIdx;
        hl.push(MockCatalog.TAGS[tIdx]);
        continue;
      }
      // e. 还在打字？
      if (last && typing.test(tk)) {
        continue;
      }
      ok = false;
    }

    const groups: QueryGroup[] = [];
    if (ok) {
      let rowOffset = 0;
      let nodeOffset = 0;
      const allowed: Set<number> | undefined = regs;
      for (let ri = 0; ri < regions.length; ri++) {
        if (allowed !== undefined && !allowed.has(ri)) {
          continue;
        }
        const g = regions[ri];
        const l = g.cities.length;
        const c = g.carriers.length;
        const hasC = car.has(ri);
        const hasT = cityTok.has(ri);
        const p = Math.max(1, (hasT ? l : 1) * ((tag >= 0 || hasC) ? 5 : 1) * (hasC ? c : 1));
        const res: number[] = [];
        for (let j = 0; j < p; j++) {
          if (hasT && j % l !== cityTok.get(ri)) {
            continue;
          }
          if (tag >= 0 && MockCatalog.tagOf(ri, j) !== tag) {
            continue;
          }
          if (hasC && MockCatalog.carOf(ri, j) !== car.get(ri)) {
            continue;
          }
          res.push(j);
        }
        let cnt = 0;
        for (const s of res) {
          if (s < g.count) {
            cnt += Math.floor((g.count - 1 - s) / p) + 1;
          }
        }
        if (cnt > 0) {
          groups.push(new QueryGroup(ri, cnt, res, p, rowOffset, nodeOffset));
          rowOffset += 1 + cnt;
          nodeOffset += cnt;
        }
      }
    }
    return new NodeQuery(raw, groups, hl);
  }

  private static meet(cur: Set<number> | undefined, s: Set<number>): Set<number> {
    if (cur === undefined) {
      return s;
    }
    const out = new Set<number>();
    s.forEach((v: number) => {
      if (cur.has(v)) {
        out.add(v);
      }
    });
    return out;
  }
}
