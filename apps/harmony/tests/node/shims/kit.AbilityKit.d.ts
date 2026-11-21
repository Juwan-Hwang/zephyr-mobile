export interface Want { bundleName?: string; abilityName?: string; uri?: string; action?: string; parameters?: Record<string, Object>; }
export namespace AbilityConstant { interface LaunchParam { launchReason?: number } }
export namespace common {
  interface ApplicationInfo { name: string }
  interface Context { filesDir: string; applicationInfo: ApplicationInfo }
  interface ApplicationContext { setColorMode(mode: ConfigurationConstant.ColorMode): void }
  interface UIAbilityContext extends Context { config: Configuration; getApplicationContext(): ApplicationContext }
}
export class UIAbility {
  context: common.UIAbilityContext;
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void;
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void;
  onDestroy(): void;
  onWindowStageCreate(windowStage: window.WindowStage): void;
  onWindowStageDestroy(): void;
  onForeground(): void;
  onConfigurationUpdate(config: Configuration): void;
  onBackground(): void;
}
import { window } from './kit.ArkUI';
export interface Configuration { colorMode?: ConfigurationConstant.ColorMode }
export namespace ConfigurationConstant { enum ColorMode { COLOR_MODE_NOT_SET = -1, COLOR_MODE_DARK = 0, COLOR_MODE_LIGHT = 1 } }
