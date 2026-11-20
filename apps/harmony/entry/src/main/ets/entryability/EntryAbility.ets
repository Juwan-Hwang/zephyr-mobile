/*
 * 主 UIAbility（最小版）：加载 pages/Index；把外链（zephyr:// clash:// clashmeta:// mihomo://）解析成导入请求放进
 * AppStorage（IMPORT_REQUEST_KEY），页面据此出确认面板（§16.e⑦，从不自动导入）。
 * 冷启动走 onCreate，已在前台 / 后台时（launchType = singleton）走 onNewWant。
 * 引擎选择（Mock / Native）、VpnController 实例化留给后续 UI 工作。
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { DeepLinks, IMPORT_REQUEST_KEY, ImportRequest } from './DeepLink';

const DOMAIN: number = 0x5A50;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleWant(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
      }
    });
  }

  private handleWant(want: Want): void {
    const req = DeepLinks.parse(want.uri, Date.now());
    if (req === undefined) {
      return;
    }
    // URI 可能带订阅 token：日志只记 scheme 和结果。
    hilog.info(DOMAIN, TAG, 'import link: %{public}s ok=%{public}s', req.scheme, String(req.payload !== undefined));
    AppStorage.setOrCreate<ImportRequest>(IMPORT_REQUEST_KEY, req);
  }
}
