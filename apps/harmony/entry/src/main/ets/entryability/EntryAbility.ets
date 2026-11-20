/*
 * 主 UIAbility：选引擎、读回落盘的设置（SettingsStore.restore）、建 VpnController、装进 AppServices（同时放进 AppStorage），再加载 pages/Index。
 * 外链（zephyr:// clash:// clashmeta:// mihomo://）解析成导入请求交给 ImportInbox（同时写 AppStorage IMPORT_REQUEST_KEY），
 * 页面据此出确认面板（§16.e⑦，从不自动导入）。冷启动走 onCreate，已在前台 / 后台时（launchType = singleton）走 onNewWant。
 *
 * 引擎：默认 MockEngine；USE_NATIVE_KEY（AppStorage）或 Want 参数 zephyr.nativeEngine = true 时用 NativeEngine，
 * 创建失败（缺 .so 等）退回 Mock 并记日志。引擎是异步建的，所以 loadContent 放在 install 之后。
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppServices, USE_NATIVE_KEY } from '../app/AppServices';
import { ImportInbox } from '../app/ImportInbox';
import { PreferencesBackend } from '../app/PreferencesBackend';
import { KeyValueBackend, MemoryBackend, SettingsStore } from '../app/SettingsStore';
import { MockEngine } from '../engine/MockEngine';
import { NativeEngine } from '../engine/native/NativeEngine';
import { ZephyrEngine } from '../engine/ZephyrEngine';
import { VpnController } from '../vpn/VpnController';
import { DeepLinks } from './DeepLink';

const DOMAIN: number = 0x5A50;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private wantsNative: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const p = want.parameters;
    const fromWant = p !== undefined && p[USE_NATIVE_KEY] === true;
    this.wantsNative = fromWant || AppStorage.get<boolean>(USE_NATIVE_KEY) === true;
    this.handleWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.createEngine().then(async (engine: ZephyrEngine) => {
      const settings = new SettingsStore(engine, await this.openBackend());
      await settings.restore();
      let vpn: VpnController | undefined = undefined;
      try {
        vpn = new VpnController(this.context);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'VpnController init failed: %{public}s', String(e));
      }
      AppServices.install(engine, vpn, settings);
      hilog.info(DOMAIN, TAG, 'engine=%{public}s vpn=%{public}s', engine.kind, String(vpn !== undefined));
      windowStage.loadContent('pages/Index', (err) => {
        if (err && err.code) {
          hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
        }
      });
    });
  }

  onForeground(): void {
    // 扩展在另一个进程：回前台时读一次 status.json（期间可能被系统停掉）。
    const vpn = AppServices.get().vpn;
    if (vpn !== undefined) {
      vpn.syncFromStatus();
    }
  }

  onDestroy(): void {
    AppServices.get().dispose();
  }

  private async openBackend(): Promise<KeyValueBackend> {
    try {
      return await PreferencesBackend.open(this.context);
    } catch (e) {
      // 拿不到 preferences 时本次运行只在内存里保存，改动不会丢在半路（下次启动回到上次成功落盘的值）。
      hilog.error(DOMAIN, TAG, 'preferences unavailable: %{public}s', String(e));
      return new MemoryBackend();
    }
  }

  private async createEngine(): Promise<ZephyrEngine> {
    if (this.wantsNative) {
      try {
        return await NativeEngine.create(this.context.filesDir);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'NativeEngine unavailable, falling back to mock: %{public}s', String(e));
      }
    }
    return new MockEngine();
  }

  private handleWant(want: Want): void {
    const req = DeepLinks.parse(want.uri, Date.now());
    if (req === undefined) {
      return;
    }
    // URI 可能带订阅 token：日志只记 scheme 和结果。
    hilog.info(DOMAIN, TAG, 'import link: %{public}s ok=%{public}s', req.scheme, String(req.payload !== undefined));
    ImportInbox.post(req);
  }
}
