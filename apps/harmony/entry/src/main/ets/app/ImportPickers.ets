/*
 * 订阅导入的系统入口（M1-12；对照 Android SubscriptionImporter.pickFile / QrScanDialog）：
 * - 文件：DocumentViewPicker 选一个文件，按 UTF-8 读出（去 BOM），超过 32 MB 视为读不了（同 Android MAX_BYTES）；
 * - 扫码：ScanKit 默认扫码界面（startScanForResult，只认二维码，允许从相册选图）；系统界面自带相机授权，应用不申请相机权限。
 * 用户取消返回 CANCELLED，界面不提示；其余失败由页面按种类给出本地化文案（§0.5，不显示系统原文）。
 */
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SubscriptionImport } from './SubscriptionImport';

export enum PickError {
  CANCELLED = 'cancelled',
  /** 文件打不开 / 读失败 / 超过 32 MB / 不是文本。 */
  UNREADABLE = 'unreadable',
  /** 本机没有扫码能力（相机不可用、服务异常）。 */
  UNAVAILABLE = 'unavailable'
}

export interface PickResult {
  text?: string;
  error?: PickError;
}

const READ_CHUNK: number = 256 * 1024;

export class ImportPickers {
  static async pickFile(ctx: common.Context): Promise<PickResult> {
    let uris: string[] = [];
    try {
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      uris = await new picker.DocumentViewPicker(ctx).select(opts);
    } catch (e) {
      const r: PickResult = { error: PickError.UNREADABLE };
      return r;
    }
    if (uris === undefined || uris.length === 0) {
      const r: PickResult = { error: PickError.CANCELLED };
      return r;
    }
    return ImportPickers.readText(uris[0]);
  }

  /** 异步分块读，不在主线程一次性同步读大文件。 */
  static async readText(uri: string): Promise<PickResult> {
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const st = await fs.stat(file.fd);
      if (!SubscriptionImport.fileSizeAllowed(st.size)) {
        const r: PickResult = { error: PickError.UNREADABLE };
        return r;
      }
      const all = new Uint8Array(st.size);
      let off = 0;
      while (off < st.size) {
        const len = Math.min(READ_CHUNK, st.size - off);
        const buf = new ArrayBuffer(len);
        const n = await fs.read(file.fd, buf, { offset: off, length: len });
        if (n <= 0) {
          break;
        }
        all.set(new Uint8Array(buf, 0, n), off);
        off += n;
      }
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const text = SubscriptionImport.stripBom(decoder.decodeToString(all.subarray(0, off)));
      const r: PickResult = text.trim().length > 0 ? { text: text } : { error: PickError.UNREADABLE };
      return r;
    } catch (e) {
      const r: PickResult = { error: PickError.UNREADABLE };
      return r;
    } finally {
      if (file !== undefined) {
        fs.close(file).catch(() => {});
      }
    }
  }

  static async scanQr(ctx: common.Context): Promise<PickResult> {
    try {
      const opts: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      };
      const res = await scanBarcode.startScanForResult(ctx, opts);
      const v = res.originalValue !== undefined ? res.originalValue.trim() : '';
      const r: PickResult = v.length > 0 ? { text: v } : { error: PickError.CANCELLED };
      return r;
    } catch (e) {
      const code = (e as BusinessError).code;
      const r: PickResult = {
        error: code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED ? PickError.CANCELLED : PickError.UNAVAILABLE
      };
      return r;
    }
  }
}
