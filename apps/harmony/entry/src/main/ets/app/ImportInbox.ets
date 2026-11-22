/*
 * 外链导入请求的进程内信箱。EntryAbility 收到 zephyr:// / clash:// 等外链后同时写 AppStorage（IMPORT_REQUEST_KEY，
 * 旧接口，保留）与这里；页面（@ComponentV2 不能用 @StorageProp）订阅本流，处理完 consume 清掉两处。
 * §16.e⑦：只出确认面板，从不自动导入。
 */
import { IMPORT_REQUEST_KEY, ImportRequest } from '../entryability/DeepLink';
import { EventStream, StateStream } from '../engine/Stream';

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

/**
 * “打开添加订阅”请求（§16.b② 无订阅时点连接）：Index 设 pending 并 emit，订阅页出现时或已在屏时展开添加区并消费。
 */
export class AddSubscriptionRequest {
  private static pending: boolean = false;
  static readonly events: EventStream<number> = new EventStream<number>();

  static request(): void {
    AddSubscriptionRequest.pending = true;
    AddSubscriptionRequest.events.emit(1);
  }

  static consume(): boolean {
    const p = AddSubscriptionRequest.pending;
    AddSubscriptionRequest.pending = false;
    return p;
  }
}
