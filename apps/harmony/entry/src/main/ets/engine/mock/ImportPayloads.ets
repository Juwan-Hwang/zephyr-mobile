import { ImportItem, ImportPayload, ImportPayloadKind } from '../Model';

/**
 * 契约 §15 parseImportPayload 的 ArkTS 版，逐行对照 Android `ImportPayloads.kt`（core-mobile `parse_import_payload` 的孪生）。
 * MockEngine 与 UI 预解析（多条确认面板、外链 want）用它；真实引擎问 core。
 * 校验样本：contract/fixtures/import-payload-v1.json（/workspace/work/ets-check 逐条比对）。
 *
 * 接受（scheme/host 不区分大小写，≤ 4096 字节，≤ 20 条）：
 * 1. `zephyr://import?url=<pct>&name=<pct>&auto=<h>`
 * 2. `zephyr://import?v=1&d=<base64url(JSON)>`，JSON = `{"v":1,"subs":[{"name","url","auto"}]}`
 * 3. `clash://` · `clashmeta://` · `mihomo://install-config?url=…&name=…`
 * 4. 裸 `http(s)://…`
 *
 * ArkTS 严格模式：不用 JSON.parse（返回值无类型），内置一个只认本格式所需的极小 JSON 解析器；UTF‑8 / base64url 也手写，
 * 不依赖 @ohos.util，便于在 node 下跑样本。
 */
export enum ImportErrorCategory {
  INVALID = 'invalid',
  SUBSCRIPTION_INVALID = 'subscription_invalid'
}

/** category 对应样本的 err；message 只进日志（§0.5）；versionTooNew 让 UI 提示“请更新 Zephyr”。 */
export class ImportPayloadError extends Error {
  category: ImportErrorCategory;
  versionTooNew: boolean;

  constructor(category: ImportErrorCategory, message: string, versionTooNew?: boolean) {
    super(message);
    this.name = 'ImportPayloadError';
    this.category = category;
    this.versionTooNew = versionTooNew === true;
  }
}

class KV {
  key: string;
  value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

enum JsonKind {
  NULL,
  BOOL,
  NUMBER,
  STRING,
  ARRAY,
  OBJECT
}

/** 极小 JSON 值：NUMBER 的 text 保留字面量（对齐 kotlinx longOrNull / intOrNull 按内容解析）。 */
class JsonValue {
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

class JsonReader {
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

export class ImportPayloads {
  static readonly MAX_ITEMS: number = 20;
  static readonly MAX_PAYLOAD_BYTES: number = 4096;
  private static readonly CLASH: string[] = ['clash://install-config', 'clashmeta://install-config', 'mihomo://install-config'];
  private static readonly B64: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static parse(payload: string): ImportPayload {
    const p = payload.trim();
    if (p.length === 0) {
      throw ImportPayloads.invalid('empty payload');
    }
    if (ImportPayloads.utf8(p).length > ImportPayloads.MAX_PAYLOAD_BYTES) {
      throw ImportPayloads.invalid('payload too long');
    }
    const lower = p.toLowerCase();
    const zq = ImportPayloads.query(p, lower, ['zephyr://import']);
    const cq = zq === undefined ? ImportPayloads.query(p, lower, ImportPayloads.CLASH) : undefined;
    let out: ImportPayload;
    if (zq !== undefined) {
      out = { kind: ImportPayloadKind.ZEPHYR, items: ImportPayloads.zephyr(zq) };
    } else if (cq !== undefined) {
      out = { kind: ImportPayloadKind.CLASH_INSTALL, items: [ImportPayloads.item(ImportPayloads.pairs(cq))] };
    } else if (lower.startsWith('http://') || lower.startsWith('https://')) {
      out = { kind: ImportPayloadKind.URL, items: [ImportPayloads.finish(undefined, p, undefined)] };
    } else {
      throw ImportPayloads.invalid('not a subscription link or Zephyr import code');
    }
    if (out.items.length === 0) {
      throw ImportPayloads.invalid('no subscriptions in payload');
    }
    if (out.items.length > ImportPayloads.MAX_ITEMS) {
      throw ImportPayloads.invalid(`at most ${ImportPayloads.MAX_ITEMS} subscriptions at once`);
    }
    return out;
  }

  /** 剪贴板里像整份 Clash / mihomo 配置（按本地配置导入，同文件）。 */
  static looksLikeConfig(payload: string): boolean {
    return payload.includes('proxies:') || payload.includes('proxy-providers:');
  }

  /** prefixes 之一（及可选 `/`）之后到 `#` 的查询串；无内容 → ""；不匹配 → undefined。 */
  private static query(orig: string, lower: string, prefixes: string[]): string | undefined {
    for (const pre of prefixes) {
      if (!lower.startsWith(pre)) {
        continue;
      }
      let rest = orig.substring(pre.length);
      if (rest.startsWith('/')) {
        rest = rest.substring(1);
      }
      if (rest.length === 0) {
        return '';
      }
      if (!rest.startsWith('?')) {
        return undefined;
      }
      const q = rest.substring(1);
      const h = q.indexOf('#');
      return h >= 0 ? q.substring(0, h) : q;
    }
    return undefined;
  }

  private static pairs(q: string): KV[] {
    const out: KV[] = [];
    for (const kv of q.split('&')) {
      if (kv.length === 0) {
        continue;
      }
      const i = kv.indexOf('=');
      out.push(i < 0 ? new KV(ImportPayloads.pct(kv), '') :
        new KV(ImportPayloads.pct(kv.substring(0, i)), ImportPayloads.pct(kv.substring(i + 1))));
    }
    return out;
  }

  private static get(ps: KV[], key: string): string | undefined {
    for (const p of ps) {
      if (p.key === key) {
        return p.value;
      }
    }
    return undefined;
  }

  private static zephyr(q: string): ImportItem[] {
    const ps = ImportPayloads.pairs(q);
    const ver = ImportPayloads.get(ps, 'v');
    if (ver !== undefined && ver !== '1') {
      throw new ImportPayloadError(ImportErrorCategory.INVALID, `import code v${ver} is too new`, true);
    }
    const d = ImportPayloads.get(ps, 'd');
    if (d === undefined) {
      return [ImportPayloads.item(ps)];
    }
    const damaged = 'import code data is damaged';
    const raw = ImportPayloads.base64Url(d);
    if (raw === undefined) {
      throw ImportPayloads.invalid(damaged);
    }
    const text = ImportPayloads.utf8Decode(raw);
    const obj = text === undefined ? undefined : JsonReader.parse(text);
    if (obj === undefined || obj.kind !== JsonKind.OBJECT) {
      throw ImportPayloads.invalid(damaged);
    }
    const vj = obj.fields.get('v');
    const v = vj !== undefined && vj.isPrimitive() ? ImportPayloads.toInt(vj.contentOrNull()) : undefined;
    if (v === undefined) {
      throw ImportPayloads.invalid(damaged);
    }
    const subs = obj.fields.get('subs');
    if (subs === undefined || subs.kind !== JsonKind.ARRAY) {
      throw ImportPayloads.invalid(damaged);
    }
    if (v !== 1) {
      throw new ImportPayloadError(ImportErrorCategory.INVALID, `import code v${v} is too new`, true);
    }
    const names: (string | undefined)[] = [];
    const urls: string[] = [];
    const autos: (number | undefined)[] = [];
    for (const s of subs.items) {
      if (s.kind !== JsonKind.OBJECT) {
        throw ImportPayloads.invalid(damaged);
      }
      const u = s.fields.get('url');
      if (u === undefined || u.kind !== JsonKind.STRING) {
        throw ImportPayloads.invalid(damaged);
      }
      const n = s.fields.get('name');
      const a = s.fields.get('auto');
      let auto: number | undefined = undefined;
      if (a !== undefined && a.isPrimitive() && a.kind !== JsonKind.NULL) {
        auto = ImportPayloads.toInt(a.text);
        if (auto === undefined) {
          throw ImportPayloads.invalid(damaged);
        }
      }
      names.push(n !== undefined && n.isPrimitive() ? n.contentOrNull() : undefined);
      urls.push(u.text);
      autos.push(auto);
    }
    const out: ImportItem[] = [];
    for (let k = 0; k < urls.length; k++) {
      out.push(ImportPayloads.finish(names[k], urls[k], autos[k]));
    }
    return out;
  }

  private static item(ps: KV[]): ImportItem {
    const url = ImportPayloads.get(ps, 'url');
    if (url === undefined) {
      throw ImportPayloads.invalid('missing url');
    }
    const a = ImportPayloads.get(ps, 'auto');
    let auto: number | undefined = undefined;
    if (a !== undefined && a.length > 0) {
      auto = ImportPayloads.toInt(a);
      if (auto === undefined) {
        throw ImportPayloads.invalid('auto is not an integer');
      }
    }
    return ImportPayloads.finish(ImportPayloads.get(ps, 'name'), url, auto);
  }

  private static finish(name: string | undefined, url: string, auto: number | undefined): ImportItem {
    const u = url.trim();
    ImportPayloads.validateUrl(u);
    const t = name === undefined ? undefined : name.trim();
    const n = t === undefined || t.length === 0 ? undefined : t;
    if (n !== undefined) {
      ImportPayloads.validateName(n);
    }
    if (auto !== undefined && (auto < 0 || auto > 720)) {
      throw ImportPayloads.invalid('auto out of range (0–720 hours)');
    }
    const item: ImportItem = { name: n, url: u, autoUpdateHours: auto };
    return item;
  }

  /** 桌面 validate_subscription_url_basic 要点：仅 http/https，`//` 后必须有主机，无控制字符。 */
  private static validateUrl(url: string): void {
    for (let i = 0; i < url.length; i++) {
      const c = url.charCodeAt(i);
      if (c < 0x20 || c === 0x7F) {
        throw ImportPayloads.subInvalid('Invalid URL: must not contain control characters');
      }
    }
    const lower = url.toLowerCase();
    let rest: string;
    if (lower.startsWith('https://')) {
      rest = lower.substring(8);
    } else if (lower.startsWith('http://')) {
      rest = lower.substring(7);
    } else {
      throw ImportPayloads.subInvalid('Only HTTP and HTTPS URLs are allowed');
    }
    if (rest.length === 0 || rest.startsWith('/') || rest.startsWith('\\')) {
      throw ImportPayloads.subInvalid('URL must have a host');
    }
    let auth = rest;
    for (const sep of ['/', '?', '#']) {
      const k = auth.indexOf(sep);
      if (k >= 0) {
        auth = auth.substring(0, k);
      }
    }
    let host = auth.substring(auth.lastIndexOf('@') + 1);
    if (host.startsWith('[')) {
      const close = host.indexOf(']');
      host = close > 0 ? host.substring(1, close) : '';
    } else {
      const colon = host.indexOf(':');
      if (colon >= 0) {
        host = host.substring(0, colon);
      }
    }
    if (host.trim().length === 0) {
      throw ImportPayloads.subInvalid('URL must have a host');
    }
  }

  /** 桌面 validate_subscription_name（→ sanitize_base_filename）要点。 */
  private static validateName(n: string): void {
    let end = n.length;
    while (end > 0 && (n.charAt(end - 1) === ' ' || n.charAt(end - 1) === '.')) {
      end--;
    }
    const t = n.substring(0, end);
    if (t.includes('/') || t.includes('\\') || t === '..' || t === '.' || t.length === 0) {
      throw ImportPayloads.subInvalid('invalid subscription name');
    }
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      if (c <= 0x1F || (c >= 0x7F && c <= 0x9F)) {
        throw ImportPayloads.subInvalid('invalid subscription name');
      }
    }
    if (ImportPayloads.utf8(t).length > 255) {
      throw ImportPayloads.subInvalid('subscription name too long');
    }
  }

  /** 百分号解码，`+` 当空格（同 core）；坏转义或解出非 UTF‑8 → invalid。 */
  private static pct(s: string): string {
    const b = ImportPayloads.utf8(s);
    const out: number[] = [];
    const hex = new RegExp('^[0-9a-fA-F]{2}$');
    let i = 0;
    while (i < b.length) {
      const c = b[i];
      if (c === 0x25) { // %
        if (i + 2 >= b.length) {
          throw ImportPayloads.invalid('bad percent-encoding');
        }
        const h = String.fromCharCode(b[i + 1], b[i + 2]);
        if (!hex.test(h)) {
          throw ImportPayloads.invalid('bad percent-encoding');
        }
        out.push(parseInt(h, 16));
        i += 3;
      } else if (c === 0x2B) { // +
        out.push(0x20);
        i++;
      } else {
        out.push(c);
        i++;
      }
    }
    const dec = ImportPayloads.utf8Decode(out);
    if (dec === undefined) {
      throw ImportPayloads.invalid('not UTF-8');
    }
    return dec;
  }

  /** 十进制整数（可带 +/-，对齐 Kotlin toIntOrNull），超出 Int32 → undefined。 */
  private static toInt(s: string | undefined): number | undefined {
    if (s === undefined || !new RegExp('^[+-]?[0-9]+$').test(s)) {
      return undefined;
    }
    const v = parseInt(s, 10);
    return v >= -2147483648 && v <= 2147483647 ? v : undefined;
  }

  private static base64Url(s: string): number[] | undefined {
    let t = s;
    while (t.endsWith('=')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.length % 4 === 1) {
      return undefined;
    }
    const out: number[] = [];
    let acc = 0;
    let bits = 0;
    for (let i = 0; i < t.length; i++) {
      const v = ImportPayloads.B64.indexOf(t.charAt(i));
      if (v < 0) {
        return undefined;
      }
      acc = ((acc << 6) | v) & 0xFFFFFF;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((acc >> bits) & 0xFF);
      }
    }
    return out;
  }

  static utf8(s: string): number[] {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      let c = s.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        const d = s.charCodeAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
          i++;
        }
      }
      if (c < 0x80) {
        out.push(c);
      } else if (c < 0x800) {
        out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
      } else if (c < 0x10000) {
        out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
      } else {
        out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 0x3F), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
      }
    }
    return out;
  }

  /** 严格 UTF‑8 解码（拒绝过长编码、代理区、> U+10FFFF）；非法 → undefined。 */
  static utf8Decode(b: number[]): string | undefined {
    let out = '';
    let i = 0;
    while (i < b.length) {
      const c = b[i];
      let need = 0;
      let cp = 0;
      let min = 0;
      if (c < 0x80) {
        out += String.fromCharCode(c);
        i++;
        continue;
      } else if (c >= 0xC2 && c <= 0xDF) {
        need = 1;
        cp = c & 0x1F;
        min = 0x80;
      } else if (c >= 0xE0 && c <= 0xEF) {
        need = 2;
        cp = c & 0x0F;
        min = 0x800;
      } else if (c >= 0xF0 && c <= 0xF4) {
        need = 3;
        cp = c & 0x07;
        min = 0x10000;
      } else {
        return undefined;
      }
      if (i + need >= b.length) {
        return undefined;
      }
      for (let k = 1; k <= need; k++) {
        const x = b[i + k];
        if ((x & 0xC0) !== 0x80) {
          return undefined;
        }
        cp = (cp << 6) | (x & 0x3F);
      }
      if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        return undefined;
      }
      out += String.fromCodePoint(cp);
      i += need + 1;
    }
    return out;
  }

  private static invalid(msg: string): ImportPayloadError {
    return new ImportPayloadError(ImportErrorCategory.INVALID, msg);
  }

  private static subInvalid(msg: string): ImportPayloadError {
    return new ImportPayloadError(ImportErrorCategory.SUBSCRIPTION_INVALID, msg);
  }
}
