/*
 * 进程级服务：引擎、设置落盘、VPN 控制器、连接编排、日志模型。EntryAbility 在 onWindowStageCreate 里 install，再 loadContent；
 * 同时把 engine / vpn 放进 AppStorage（ENGINE_KEY / VPN_KEY），供旧式 @StorageProp 页面或调试读取。
 * 页面一律经 AppServices.get() 取用：DevEco 预览器不跑 UIAbility，get() 会退回一个演示用 MockEngine（无 VPN）。
 *
 * 引擎选择：默认 MockEngine；AppStorage[USE_NATIVE_KEY] === true 或启动 Want 参数 zephyr.nativeEngine = true 时
 * 用 NativeEngine（`hdc shell aa start -a EntryAbility -b <bundle> --pb zephyr.nativeEngine true`），创建失败退回 Mock。
 */
import { ZephyrEngine } from '../engine/ZephyrEngine';
import { MockEngine } from '../engine/MockEngine';
import { VpnController } from '../vpn/VpnController';
import { ConnectionCoordinator } from './ConnectionCoordinator';
import { LogsModel } from './LogsModel';
import { MemoryBackend, SettingsStore } from './SettingsStore';

export const ENGINE_KEY: string = 'zephyr.engine';
export const VPN_KEY: string = 'zephyr.vpn';
/** 调试开关：true = 用 NativeEngine（需打进 libcore_ohos.so）。 */
export const USE_NATIVE_KEY: string = 'zephyr.nativeEngine';

export class AppServices {
  readonly engine: ZephyrEngine;
  readonly vpn: VpnController | undefined;
  readonly connection: ConnectionCoordinator;
  readonly logs: LogsModel;
  /** 页面改设置一律经 settings.update（落盘 + 失败回滚）。 */
  readonly settings: SettingsStore;

  private static instance: AppServices | undefined = undefined;

  private constructor(engine: ZephyrEngine, vpn: VpnController | undefined, settings: SettingsStore) {
    this.engine = engine;
    this.settings = settings;
    this.vpn = vpn;
    this.connection = new ConnectionCoordinator(engine, vpn);
    this.logs = new LogsModel(engine);
  }

  static install(engine: ZephyrEngine, vpn: VpnController | undefined, settings: SettingsStore): AppServices {
    if (AppServices.instance !== undefined) {
      AppServices.instance.dispose();
    }
    const s = new AppServices(engine, vpn, settings);
    AppServices.instance = s;
    AppStorage.setOrCreate<ZephyrEngine>(ENGINE_KEY, engine);
    if (vpn !== undefined) {
      AppStorage.setOrCreate<VpnController>(VPN_KEY, vpn);
    }
    return s;
  }

  static get(): AppServices {
    if (AppServices.instance === undefined) {
      // 预览器 / 单测：没有 UIAbility，用演示数据（已连接 2:14:07）。
      const engine = new MockEngine({ demo: true });
      AppServices.instance = new AppServices(engine, undefined, new SettingsStore(engine, new MemoryBackend()));
    }
    return AppServices.instance;
  }

  dispose(): void {
    this.settings.dispose();
    this.connection.dispose();
    this.logs.stop();
    if (this.vpn !== undefined) {
      this.vpn.dispose();
    }
  }
}
