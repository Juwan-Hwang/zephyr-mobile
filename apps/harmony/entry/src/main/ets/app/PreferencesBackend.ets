/*
 * SettingsStore 的真机后端：@kit.ArkData preferences（文件 'zephyr'，应用沙箱 el2）。
 * put 后立即 flush，flush 失败即 reject，SettingsStore 据此回滚。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { KeyValueBackend } from './SettingsStore';

export class PreferencesBackend implements KeyValueBackend {
  private prefs: preferences.Preferences;

  private constructor(prefs: preferences.Preferences) {
    this.prefs = prefs;
  }

  static async open(context: common.Context): Promise<PreferencesBackend> {
    const p = await preferences.getPreferences(context, { name: 'zephyr' } as preferences.Options);
    return new PreferencesBackend(p);
  }

  async get(key: string): Promise<string | undefined> {
    const v = await this.prefs.get(key, '');
    return typeof v === 'string' && v.length > 0 ? v : undefined;
  }

  async put(key: string, value: string): Promise<void> {
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }
}
