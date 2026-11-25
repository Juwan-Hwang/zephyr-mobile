/*
 * 胶囊按钮（同 Android ZButton / 原型 .btn）：
 * - Compact 40 高、14 Medium、左右 18；Large 52 高、16、左右 22。
 * - Primary = screen_primary 填充；Secondary = hairline 填充、t1 字（.btn.q）；Ghost = 透明、强调色字；
 *   Danger = 红字、红 14% 底；Accent = 强调色填充、白字；Toolbar = 透明、强调色 16 号常规、左右 8（同 Android 日志页 ToolbarText）。
 * - 按压缩到 0.97（tokens motion.press-scale），不用系统按压蒙层；禁用 0.4 不透明。
 * 用法：Button(x).attributeModifier(ZBtn.secondary())，宽度/layoutWeight 在调用处另设。
 */
import { ZMotion } from '../generated/ZTokens';

export enum ZBtnKind { PRIMARY, SECONDARY, GHOST, DANGER, ACCENT, TOOLBAR }

export class ZBtn implements AttributeModifier<ButtonAttribute> {
  private kind: ZBtnKind;
  private large: boolean;
  private accent: ResourceColor;

  constructor(kind: ZBtnKind, large: boolean = false, accent: ResourceColor = '#FF007AFF') {
    this.kind = kind;
    this.large = large;
    this.accent = accent;
  }

  static primary(large: boolean = false): ZBtn {
    return new ZBtn(ZBtnKind.PRIMARY, large);
  }

  static secondary(large: boolean = false): ZBtn {
    return new ZBtn(ZBtnKind.SECONDARY, large);
  }

  static ghost(accent: ResourceColor): ZBtn {
    return new ZBtn(ZBtnKind.GHOST, false, accent);
  }

  static danger(): ZBtn {
    return new ZBtn(ZBtnKind.DANGER);
  }

  static toolbar(accent: ResourceColor): ZBtn {
    return new ZBtn(ZBtnKind.TOOLBAR, false, accent);
  }

  static accentFill(accent: ResourceColor, large: boolean = false): ZBtn {
    return new ZBtn(ZBtnKind.ACCENT, large, accent);
  }

  private base(b: ButtonAttribute): void {
    b.type(ButtonType.Capsule)
      .stateEffect(false)
      .height(this.large ? 52 : 40)
      .constraintSize({ minWidth: this.kind === ZBtnKind.TOOLBAR ? 0 : 64 })
      .padding(this.kind === ZBtnKind.TOOLBAR ? { left: 8, right: 8 } : { left: this.large ? 22 : 18, right: this.large ? 22 : 18 })
      .fontSize(this.large || this.kind === ZBtnKind.TOOLBAR ? 16 : 14)
      .fontWeight(this.large || this.kind === ZBtnKind.TOOLBAR ? FontWeight.Regular : FontWeight.Medium)
      .opacity(1)
      .scale({ x: 1, y: 1 })
      .animation({ duration: 120, curve: Curve.EaseOut });
    switch (this.kind) {
      case ZBtnKind.PRIMARY:
        b.backgroundColor($r('app.color.screen_primary')).fontColor($r('app.color.screen_on_primary'));
        break;
      case ZBtnKind.SECONDARY:
        b.backgroundColor($r('app.color.screen_hl')).fontColor($r('app.color.screen_t1'));
        break;
      case ZBtnKind.GHOST:
      case ZBtnKind.TOOLBAR:
        b.backgroundColor(Color.Transparent).fontColor(this.accent);
        break;
      case ZBtnKind.DANGER:
        b.backgroundColor('#24FF3B30').fontColor($r('app.color.screen_red_text'));
        break;
      default:
        b.backgroundColor(this.accent).fontColor(Color.White);
    }
  }

  applyNormalAttribute(b: ButtonAttribute): void {
    this.base(b);
  }

  applyPressedAttribute(b: ButtonAttribute): void {
    this.base(b);
    b.scale({ x: ZMotion.pressScale, y: ZMotion.pressScale });
  }

  applyDisabledAttribute(b: ButtonAttribute): void {
    this.base(b);
    b.opacity(0.4);
  }
}
