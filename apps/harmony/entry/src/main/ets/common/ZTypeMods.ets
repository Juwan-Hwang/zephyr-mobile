/*
 * 原型字阶（同 Android ZTypography）：大数字和状态标题用细字重 + 等宽数字（tnum），不用 monospace 字体。
 * 用法：Text(x).attributeModifier(ZHero.status())。
 */

/** 首页“已连接”：44 / ExtraLight / -0.035em。 */
export class StatusText implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(t: TextAttribute): void {
    t.fontSize(44).fontWeight(200).letterSpacing(-1.5).lineHeight(50).maxLines(1)
      .minFontSize(26).maxFontSize(44).textOverflow({ overflow: TextOverflow.Clip });
  }
}

/** 2.8 MB/s、13,109,802：56 / ExtraLight / tnum。 */
export class HeroText implements AttributeModifier<TextAttribute> {
  private size: number;

  constructor(size: number) {
    this.size = size;
  }

  applyNormalAttribute(t: TextAttribute): void {
    t.fontSize(this.size).fontWeight(200).letterSpacing(-this.size * 0.045).lineHeight(this.size + 4)
      .fontFeature('"tnum" on').maxLines(1).minFontSize(Math.round(this.size * 0.6)).maxFontSize(this.size)
      .textOverflow({ overflow: TextOverflow.Clip });
  }
}

/** 1.8 GB 今日卡：84 / ExtraLight。 */
export class DisplayText implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(t: TextAttribute): void {
    t.fontSize(84).fontWeight(200).letterSpacing(-5).lineHeight(88).fontFeature('"tnum" on').maxLines(1)
      .minFontSize(48).maxFontSize(84).textOverflow({ overflow: TextOverflow.Clip });
  }
}

/** 卡片内数字（512 节点）：30 / ExtraLight。 */
export class NumberText implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(t: TextAttribute): void {
    t.fontSize(30).fontWeight(200).letterSpacing(-0.9).lineHeight(36).fontFeature('"tnum" on');
  }
}

/** 正文里的数字（时长、延迟）：常规字重 + tnum。 */
export class NumericText implements AttributeModifier<TextAttribute> {
  private size: number;

  constructor(size: number) {
    this.size = size;
  }

  applyNormalAttribute(t: TextAttribute): void {
    t.fontSize(this.size).fontWeight(FontWeight.Normal).fontFeature('"tnum" on');
  }
}

export class ZHero {
  static status(): StatusText {
    return new StatusText();
  }

  /** size 默认 56；规则页用 48（Android hero × 0.86）。 */
  static hero(size: number = 56): HeroText {
    return new HeroText(size);
  }

  static display(): DisplayText {
    return new DisplayText();
  }

  static number(): NumberText {
    return new NumberText();
  }

  static numeric(size: number): NumericText {
    return new NumericText(size);
  }
}
