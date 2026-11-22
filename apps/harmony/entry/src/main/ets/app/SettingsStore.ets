/*
 * 设置落盘（契约 §16.c / E42，对照 Android `SettingsStore.kt`）。
 * - 启动：读整份设置 JSON → SettingsCodec 逐字段宽松解码 → engine.updateSettings 回放；再回放代理模式（Mock 引擎不自己落盘）。
 *   EntryAbility 在 loadContent 之前 await restore()，按需连接等逻辑读到的就是落盘值。
 * - 写：页面一律经 update(next)：先乐观写引擎，再写盘；写盘失败把引擎回滚到上一份已落盘的值并抛错，由页面提示（不静默）。
 * - 模式：跟随 connectionState.mode 变化写盘（只在值变化时写）。
 * 存储后端抽象成 KeyValueBackend：真机用 @kit.ArkData preferences（PreferencesBackend.ets），预览器 / 单测用内存实现。
 */
import { copySettings, ConnectionState, ErrorCode, ProxyMode, Settings } from '../engine/Model';
import { SettingsCodec } from '../engine/SettingsCodec';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZephyrEngine, ZephyrError } from '../engine/ZephyrEngine';

export interface KeyValueBackend {
  get(key: string): Promise<string | undefined>;
  /** 写入并刷到磁盘；失败时 reject。 */
  put(key: string, value: string): Promise<void>;
}

export class MemoryBackend implements KeyValueBackend {
  readonly values: Map<string, string> = new Map<string, string>();

  async get(key: string): Promise<string | undefined> {
    return this.values.get(key);
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

export const KEY_SETTINGS: string = 'settings_v0';
export const KEY_MODE: string = 'mode';
/** 引导页走完（Android SettingsStore.onboarded）。 */
export const KEY_ONBOARDED: string = 'onboarded';

export class SettingsStore {
  private engine: ZephyrEngine;
  private backend: KeyValueBackend;
  /** 最后一份成功落盘的设置 JSON（回滚用）。 */
  private persisted: string;
  private persistedMode: ProxyMode;
  private modeSub: StreamSub | undefined = undefined;

  constructor(engine: ZephyrEngine, backend: KeyValueBackend) {
    this.engine = engine;
    this.backend = backend;
    this.persisted = SettingsCodec.encode(engine.settings().value);
    this.persistedMode = engine.connectionState().value.mode;
  }

  /** 读盘并回放进引擎；任何一步失败都保留引擎当前值（首次安装 = 默认值）。之后开始跟随模式变化。 */
  async restore(): Promise<void> {
    try {
      const raw = await this.backend.get(KEY_SETTINGS);
      if (raw !== undefined && raw.length > 0) {
        await this.engine.updateSettings(SettingsCodec.decode(raw));
        this.persisted = SettingsCodec.encode(this.engine.settings().value);
      }
    } catch (e) {
      // 读失败：用默认值继续，下次 update 会覆盖写。
    }
    try {
      const m = SettingsCodec.proxyMode(await this.backend.get(KEY_MODE));
      if (m !== undefined && m !== this.engine.connectionState().value.mode) {
        await this.engine.setMode(m);
      }
    } catch (e) {
      // 同上。
    }
    this.persistedMode = this.engine.connectionState().value.mode;
    this.watchMode();
  }

  /** 页面改设置的唯一入口：全量写回 next。写盘失败回滚并抛 ZephyrError(internal)。 */
  async update(next: Settings): Promise<void> {
    const before = this.persisted;
    await this.engine.updateSettings(copySettings(next));
    const json = SettingsCodec.encode(this.engine.settings().value);
    if (json === before) {
      return;
    }
    try {
      await this.backend.put(KEY_SETTINGS, json);
      this.persisted = json;
    } catch (e) {
      await this.engine.updateSettings(SettingsCodec.decode(before)).catch(() => {});
      throw new ZephyrError(ErrorCode.INTERNAL, 'settings write failed');
    }
  }

  /** 是否已走完引导；读失败当作已走完（宁可不打扰老用户，同 Android 读不到时不闪引导页）。 */
  async onboarded(): Promise<boolean> {
    try {
      return (await this.backend.get(KEY_ONBOARDED)) === '1';
    } catch (e) {
      return true;
    }
  }

  async setOnboarded(): Promise<void> {
    try {
      await this.backend.put(KEY_ONBOARDED, '1');
    } catch (e) {
      // 写失败：下次启动再走一遍引导，不影响本次。
    }
  }

  dispose(): void {
    if (this.modeSub !== undefined) {
      this.modeSub.cancel();
      this.modeSub = undefined;
    }
  }

  private watchMode(): void {
    if (this.modeSub !== undefined) {
      return;
    }
    this.modeSub = this.engine.connectionState().subscribe((c: ConnectionState) => {
      if (c.mode === this.persistedMode) {
        return;
      }
      const m = c.mode;
      this.backend.put(KEY_MODE, m as string).then(() => {
        this.persistedMode = m;
      }).catch(() => {});
    });
  }
}
