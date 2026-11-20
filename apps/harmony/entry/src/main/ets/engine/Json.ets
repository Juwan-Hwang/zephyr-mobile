/*
 * 极小 JSON 读取器（ArkTS 严格模式无 any：JSON.parse 的结果不能按字段宽松取值）。
 * 用于导入载荷（§15）与设置逐字段宽松解码（§16.c E42）。
 */

export enum JsonKind {
  NULL,
  BOOL,
  NUMBER,
  STRING,
  ARRAY,
  OBJECT
}

/** 极小 JSON 值：NUMBER 的 text 保留字面量（对齐 kotlinx longOrNull / intOrNull 按内容解析）。 */
export class JsonValue {
  kind: JsonKind;
  text: string = '';
  items: JsonValue[] = [];
  fields: Map<string, JsonValue> = new Map<string, JsonValue>();

  constructor(kind: JsonKind) {
    this.kind = kind;
  }

  isPrimitive(): boolean {
    return this.kind !== JsonKind.ARRAY && this.kind !== JsonKind.OBJECT;
  }

  /** kotlinx `contentOrNull`：JsonNull → undefined，其余原始值 → 内容文本。 */
  contentOrNull(): string | undefined {
    return this.kind === JsonKind.NULL ? undefined : this.text;
  }
}

export class JsonReader {
  private s: string;
  private i: number = 0;

  constructor(s: string) {
    this.s = s;
  }

  /** 解析整段文本；任何语法错误返回 undefined。 */
  static parse(s: string): JsonValue | undefined {
    const r = new JsonReader(s);
    const v = r.value();
    if (v === undefined) {
      return undefined;
    }
    r.ws();
    return r.i === r.s.length ? v : undefined;
  }

  private ws(): void {
    while (this.i < this.s.length) {
      const c = this.s.charAt(this.i);
      if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
        this.i++;
      } else {
        break;
      }
    }
  }

  private lit(word: string): boolean {
    if (this.s.startsWith(word, this.i)) {
      this.i += word.length;
      return true;
    }
    return false;
  }

  private value(): JsonValue | undefined {
    this.ws();
    if (this.i >= this.s.length) {
      return undefined;
    }
    const c = this.s.charAt(this.i);
    if (c === '{') {
      return this.object();
    }
    if (c === '[') {
      return this.array();
    }
    if (c === '"') {
      const str = this.string();
      if (str === undefined) {
        return undefined;
      }
      const v = new JsonValue(JsonKind.STRING);
      v.text = str;
      return v;
    }
    if (this.lit('null')) {
      return new JsonValue(JsonKind.NULL);
    }
    if (this.lit('true')) {
      const t = new JsonValue(JsonKind.BOOL);
      t.text = 'true';
      return t;
    }
    if (this.lit('false')) {
      const f = new JsonValue(JsonKind.BOOL);
      f.text = 'false';
      return f;
    }
    const m = new RegExp('^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?').exec(this.s.substring(this.i));
    if (m === null || m[0].length === 0) {
      return undefined;
    }
    this.i += m[0].length;
    const n = new JsonValue(JsonKind.NUMBER);
    n.text = m[0];
    return n;
  }

  private object(): JsonValue | undefined {
    this.i++; // {
    const o = new JsonValue(JsonKind.OBJECT);
    this.ws();
    if (this.lit('}')) {
      return o;
    }
    while (true) {
      this.ws();
      if (this.s.charAt(this.i) !== '"') {
        return undefined;
      }
      const k = this.string();
      if (k === undefined) {
        return undefined;
      }
      this.ws();
      if (!this.lit(':')) {
        return undefined;
      }
      const v = this.value();
      if (v === undefined) {
        return undefined;
      }
      o.fields.set(k, v);
      this.ws();
      if (this.lit(',')) {
        continue;
      }
      if (this.lit('}')) {
        return o;
      }
      return undefined;
    }
  }

  private array(): JsonValue | undefined {
    this.i++; // [
    const a = new JsonValue(JsonKind.ARRAY);
    this.ws();
    if (this.lit(']')) {
      return a;
    }
    while (true) {
      const v = this.value();
      if (v === undefined) {
        return undefined;
      }
      a.items.push(v);
      this.ws();
      if (this.lit(',')) {
        continue;
      }
      if (this.lit(']')) {
        return a;
      }
      return undefined;
    }
  }

  private string(): string | undefined {
    this.i++; // "
    let out = '';
    while (this.i < this.s.length) {
      const c = this.s.charAt(this.i);
      const code = this.s.charCodeAt(this.i);
      this.i++;
      if (c === '"') {
        return out;
      }
      if (code < 0x20) {
        return undefined;
      }
      if (c !== '\\') {
        out += c;
        continue;
      }
      if (this.i >= this.s.length) {
        return undefined;
      }
      const e = this.s.charAt(this.i);
      this.i++;
      if (e === '"' || e === '\\' || e === '/') {
        out += e;
      } else if (e === 'b') {
        out += '\b';
      } else if (e === 'f') {
        out += '\f';
      } else if (e === 'n') {
        out += '\n';
      } else if (e === 'r') {
        out += '\r';
      } else if (e === 't') {
        out += '\t';
      } else if (e === 'u') {
        const hex = this.s.substring(this.i, this.i + 4);
        if (!new RegExp('^[0-9a-fA-F]{4}$').test(hex)) {
          return undefined;
        }
        out += String.fromCharCode(parseInt(hex, 16));
        this.i += 4;
      } else {
        return undefined;
      }
    }
    return undefined;
  }
}
