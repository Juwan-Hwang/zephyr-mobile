/*
 * 外链导入请求的进程内信箱。EntryAbility 收到 zephyr:// / clash:// 等外链后同时写 AppStorage（IMPORT_REQUEST_KEY，
 * 旧接口，保留）与这里；页面（@ComponentV2 不能用 @StorageProp）订阅本流，处理完 consume 清掉两处。
 * §16.e⑦：只出确认面板，从不自动导入。
 */
import { IMPORT_REQUEST_KEY, ImportRequest } from '../entryability/DeepLink';
import { StateStream } from '../engine/Stream';

export class ImportInbox {
  private static readonly state: StateStream<ImportRequest | undefined> = new StateStream<ImportRequest | undefined>(undefined);

  static stream(): StateStream<ImportRequest | undefined> {
    return ImportInbox.state;
  }

  static post(req: ImportRequest): void {
    AppStorage.setOrCreate<ImportRequest>(IMPORT_REQUEST_KEY, req);
    ImportInbox.state.value = req;
  }

  /** 确认 / 取消后调用；id 不是当前请求（期间又来了新链接）则不清。 */
  static consume(id: number): void {
    const cur = ImportInbox.state.value;
    if (cur !== undefined && cur.id === id) {
      AppStorage.delete(IMPORT_REQUEST_KEY);
      ImportInbox.state.value = undefined;
    }
  }
}
