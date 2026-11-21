/*
 * 契约 §0.2 的 Stream 在 ArkTS 里的最小实现（无 Flow / AsyncStream）。
 * - StateStream：热流，订阅时立即回放当前值（connectionState / scenes / settings …）。
 * - EventStream：只推新事件（latencyUpdates / logs …）。
 * 回调都在 ArkTS 主线程（事件循环）上执行；引擎内部不跨线程，故无需加锁。
 */

export type Listener<T> = (value: T) => void;

/** 取消订阅句柄。页面 aboutToDisappear 里必须调用，否则引擎会一直持有组件。 */
export class Subscription {
  private onCancel: () => void;
  private cancelled: boolean = false;

  constructor(onCancel: () => void) {
    this.onCancel = onCancel;
  }

  cancel(): void {
    if (!this.cancelled) {
      this.cancelled = true;
      this.onCancel();
    }
  }
}

export class EventStream<T> {
  protected listeners: Listener<T>[] = [];
  /** 第一个订阅者到来 / 最后一个离开时回调，供按需启动的定时器（traffic、logs）使用。 */
  onActive?: () => void;
  onIdle?: () => void;

  subscribe(listener: Listener<T>): Subscription {
    this.listeners.push(listener);
    if (this.listeners.length === 1 && this.onActive !== undefined) {
      this.onActive();
    }
    return new Subscription(() => {
      const i = this.listeners.indexOf(listener);
      if (i >= 0) {
        this.listeners.splice(i, 1);
      }
      if (this.listeners.length === 0 && this.onIdle !== undefined) {
        this.onIdle();
      }
    });
  }

  emit(value: T): void {
    // 拷贝一份：回调里取消订阅不影响本轮分发。
    const snapshot = this.listeners.slice();
    for (const l of snapshot) {
      l(value);
    }
  }

  get subscriberCount(): number {
    return this.listeners.length;
  }
}

export class StateStream<T> extends EventStream<T> {
  private current: T;

  constructor(initial: T) {
    super();
    this.current = initial;
  }

  get value(): T {
    return this.current;
  }

  set value(v: T) {
    this.current = v;
    this.emit(v);
  }

  subscribe(listener: Listener<T>): Subscription {
    const sub = super.subscribe(listener);
    listener(this.current);
    return sub;
  }
}

export function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, Math.max(0, ms));
  });
}
