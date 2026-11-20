/*
 * 订阅导入的非界面部分（对照 Android SubscriptionImporter）：粘贴 / 链接导入、外链确认后的逐条导入、http 警告判定。
 * 结果只给计数与错误码，文案由页面按码本地化（§0.5）。
 */
import { ErrorCode, ImportItem, ImportSource, Subscription } from '../engine/Model';
import { ZephyrEngine, ZephyrError } from '../engine/ZephyrEngine';

export interface ImportOutcome {
  added: number;
  failed: number;
  /** 第一个导入成功的订阅（“已添加 X”提示用）。 */
  first?: Subscription;
  /** 第一个失败的错误码。 */
  error?: ErrorCode;
}

export class SubscriptionImport {
  /** 明文 http 链接：确认面板显示“此链接未加密”警告。 */
  static isInsecure(url: string): boolean {
    return url.trim().toLowerCase().startsWith('http://');
  }

  /** 输入框 / 剪贴板：整段交给引擎（§15 规则与核心一致：链接、zephyr:// 导入码、clash 外链、配置全文）。 */
  static async importText(engine: ZephyrEngine, source: ImportSource, text: string): Promise<ImportOutcome> {
    const t = text.trim();
    if (t.length === 0) {
      const empty: ImportOutcome = { added: 0, failed: 1, error: ErrorCode.SUBSCRIPTION_INVALID };
      return empty;
    }
    try {
      const s = await engine.importSubscription(source, t);
      const ok: ImportOutcome = { added: 1, failed: 0, first: s };
      return ok;
    } catch (e) {
      const bad: ImportOutcome = { added: 0, failed: 1, error: ZephyrError.from(e as Object).code };
      return bad;
    }
  }

  /** 外链确认面板“添加”：逐条导入，部分失败照样继续。 */
  static async importItems(engine: ZephyrEngine, source: ImportSource, items: ImportItem[]): Promise<ImportOutcome> {
    const out: ImportOutcome = { added: 0, failed: 0 };
    for (const it of items) {
      try {
        const s = await engine.importItem(source, it);
        out.added++;
        if (out.first === undefined) {
          out.first = s;
        }
      } catch (e) {
        out.failed++;
        if (out.error === undefined) {
          out.error = ZephyrError.from(e as Object).code;
        }
      }
    }
    return out;
  }

  /** 确认面板里一条的显示名：有名字用名字，否则用链接的主机名。 */
  static displayName(it: ImportItem): string {
    if (it.name !== undefined && it.name.trim().length > 0) {
      return it.name.trim();
    }
    const m = new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)').exec(it.url.trim());
    return m !== null ? m[1] : it.url;
  }
}
