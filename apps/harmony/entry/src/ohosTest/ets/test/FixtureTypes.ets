/** contract/fixtures 的形状（只声明测试用到的字段）。 */

export interface FxRegion {
  index: number;
  code: string;
  name: string;
  count: number;
  cities: string[];
  baseLatency: number;
  carriers: string[];
}

export interface FxNode {
  id: number;
  region: number;
  index: number;
  name: string;
  tag: string;
  protocol: string;
  carrier: string;
  hash: number;
  cachedLatency: number | null;
}

export interface FxSection {
  region: string;
  count: number;
}

/** 首屏行：分区头只有 header，节点行只有 id + name。 */
export interface FxRow {
  header?: string;
  id?: number;
  name?: string;
}

export interface FxQuery {
  query: string;
  total: number;
  sections: FxSection[];
  firstRows: FxRow[];
}

export interface FxLayer {
  index: number;
  kind: string;
  name: string;
  count: number;
  note: string;
}

export interface FxRuleTest {
  input: string;
  layerIndex: number | null;
  rule: string;
  ruleNo: number | null;
  policy: string;
}

export interface FxRules {
  layers: FxLayer[];
  total: number;
  tests: FxRuleTest[];
}

export interface MockV0 {
  total: number;
  regions: FxRegion[];
  tags: string[];
  protocols: string[];
  nodes: FxNode[];
  queries: FxQuery[];
  rules: FxRules;
}

export interface FxImportItem {
  name: string | null;
  url: string;
  autoUpdateHours: number | null;
}

export interface FxImportOk {
  kind: string;
  items: FxImportItem[];
}

export interface FxImportCase {
  id: string;
  input: string;
  ok?: FxImportOk;
  err?: string;
}

export interface ImportPayloadV1 {
  cases: FxImportCase[];
}

export interface FxUhdCase {
  name: string;
  uhd: boolean;
}

export interface UhdNamesV1 {
  cases: FxUhdCase[];
}
