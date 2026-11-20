/*
 * 外链导入（契约 §16.e⑦）：zephyr://import、clash:// / clashmeta:// / mihomo://install-config。
 * 只解析成 ImportRequest 放进 AppStorage，由页面出确认面板；**从不自动导入**。
 * 解析与 engine.parseImportPayload 同一实现（ImportPayloads，§15），失败也保留请求，让页面显示原因。
 * http(s) 链接不经外链进来（module.json5 只声明了上述 scheme），这里也不接受。
 */
import { ErrorCode, ImportPayload } from '../engine/Model';
import { ImportPayloadError, ImportPayloads } from '../engine/mock/ImportPayloads';

/** AppStorage 键：最近一次外链导入请求（ImportRequest）。页面处理完后应 AppStorage.delete。 */
export const IMPORT_REQUEST_KEY: string = 'zephyr.importRequest';

export interface ImportRequest {
  /** 进程内递增；同一链接打开两次也能被页面识别为新请求。 */
  id: number;
  uri: string;
  /** 小写 scheme：zephyr / clash / clashmeta / mihomo。 */
  scheme: string;
  receivedAt: number;
  /** 解析成功时有值。 */
  payload?: ImportPayload;
  /** 解析失败：ErrorCode 序列化名（subscription_invalid）。 */
  errorCode?: string;
  /** 只进日志 / 调试。 */
  errorMessage?: string;
}

const PREFIXES: string[] = ['zephyr://import', 'clash://install-config', 'clashmeta://install-config', 'mihomo://install-config'];

let nextId: number = 1;

export class DeepLinks {
  /** 不是这四种外链 → undefined（Want 是桌面图标启动等）。 */
  static parse(uri: string | undefined, now: number): ImportRequest | undefined {
    if (uri === undefined) {
      return undefined;
    }
    const u = uri.trim();
    const lower = u.toLowerCase();
    let matched = false;
    for (const p of PREFIXES) {
      if (lower.startsWith(p)) {
        const rest = lower.substring(p.length);
        // 只认前缀后紧跟 ? / '/' / # 或结束，避免 clash://install-configx 之类。
        if (rest.length === 0 || rest.startsWith('?') || rest.startsWith('/') || rest.startsWith('#')) {
          matched = true;
          break;
        }
      }
    }
    if (!matched) {
      return undefined;
    }
    const req: ImportRequest = {
      id: nextId++,
      uri: u,
      scheme: lower.substring(0, lower.indexOf(':')),
      receivedAt: now
    };
    try {
      req.payload = ImportPayloads.parse(u);
    } catch (e) {
      req.errorCode = ErrorCode.SUBSCRIPTION_INVALID;
      req.errorMessage = e instanceof ImportPayloadError ? (e as ImportPayloadError).message : 'invalid';
    }
    return req;
  }
}
