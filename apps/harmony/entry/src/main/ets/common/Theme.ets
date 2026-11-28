/*
 * 运行时主题（§16.c accent / appearance，U30）。
 * - 深浅色：EntryAbility 按设置调 ApplicationContext.setColorMode（跟随系统 = COLOR_MODE_NOT_SET），资源色 $r('app.color.*')
 *   自动跟随；isDark 由 onConfigurationUpdate 更新，只用于强调色取深色变体。
 * - 强调色：4 种（tokens ZAccent），深色下用 iOS 深色系统色变体（与 Android ZAccent.darkVariant 同值）。
 * 组件持有 `@Local theme: ZTheme = ZTheme.shared()`，读 theme.accentColor()；@Trace 字段变化即重绘。
 */
import { AppStorageV2 } from '@kit.ArkUI';
import { Accent } from '../engine/Model';
import { ZAccent } from '../generated/ZTokens';

const THEME_KEY: string = 'zephyr.theme';

export function accentLight(a: Accent): string {
  switch (a) {
    case Accent.GREEN:
      return ZAccent.GREEN;
    case Accent.ORANGE:
      return ZAccent.ORANGE;
    case Accent.PINK:
      return ZAccent.PINK;
    default:
      return ZAccent.BLUE;
  }
}

/** 原型深色模式用 iOS 深色变体系统色。 */
export function accentDark(a: Accent): string {
  switch (a) {
    case Accent.GREEN:
      return '#FF30D158';
    case Accent.ORANGE:
      return '#FFFF9F0A';
    case Accent.PINK:
      return '#FFFF375F';
    default:
      return '#FF0A84FF';
  }
}

@ObservedV2
export class ZTheme {
  @Trace accent: Accent = Accent.BLUE;
  @Trace isDark: boolean = false;

  static shared(): ZTheme {
    return AppStorageV2.connect<ZTheme>(ZTheme, THEME_KEY, () => new ZTheme())!;
  }

  accentColor(): string {
    return this.isDark ? accentDark(this.accent) : accentLight(this.accent);
  }

  /** 选中态等浅底（16% 不透明度，与 Android accentSoft 同）。 */
  accentSoft(): string {
    return '#29' + this.accentColor().substring(3);
  }
}
