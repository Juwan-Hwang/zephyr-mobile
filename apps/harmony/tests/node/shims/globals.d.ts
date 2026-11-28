declare function setTimeout(cb: () => void, ms?: number): number;
declare function clearTimeout(id?: number): void;
declare function setInterval(cb: () => void, ms?: number): number;
declare function clearInterval(id?: number): void;
declare class AppStorage {
  static setOrCreate<T>(key: string, value: T): void;
  static get<T>(key: string): T | undefined;
  static delete(key: string): boolean;
}
interface Resource { bundleName: string; moduleName: string; id: number; params?: Object[]; type?: number }
type ResourceStr = string | Resource;
type ResourceColor = string | number | Resource;
declare function $r(name: string, ...args: Object[]): Resource;
interface DataChangeListener { onDataReloaded(): void; onDataAdd(index: number): void; onDataChange(index: number): void; onDataDelete(index: number): void; }
interface IDataSource { totalCount(): number; getData(index: number): Object; registerDataChangeListener(listener: DataChangeListener): void; unregisterDataChangeListener(listener: DataChangeListener): void; }
declare function ObservedV2<T extends new (...args: any[]) => object>(c: T): T;
declare function Trace(target: undefined, context: ClassFieldDecoratorContext): void;
// common/ZTypeMods.ets（AttributeModifier 字阶）只需类型可解析。
declare enum FontWeight { Normal, Regular, Medium, Bold }
declare enum TextOverflow { Clip, Ellipsis }
interface TextAttribute {
  fontSize(v: number): TextAttribute; fontWeight(v: number | FontWeight): TextAttribute; letterSpacing(v: number): TextAttribute;
  lineHeight(v: number): TextAttribute; fontFeature(v: string): TextAttribute; maxLines(v: number): TextAttribute;
  minFontSize(v: number): TextAttribute; maxFontSize(v: number): TextAttribute; textOverflow(v: { overflow: TextOverflow }): TextAttribute;
}
interface AttributeModifier<T> { applyNormalAttribute?(instance: T): void; }
declare enum ButtonType { Capsule, Circle, Normal }
declare enum Color { White, Black, Transparent }
declare enum Curve { Linear, EaseOut, EaseIn }
interface ButtonAttribute {
  type(v: ButtonType): ButtonAttribute; stateEffect(v: boolean): ButtonAttribute; height(v: number): ButtonAttribute;
  constraintSize(v: { minWidth?: number }): ButtonAttribute;
  padding(v: { left?: number; right?: number }): ButtonAttribute; fontSize(v: number): ButtonAttribute;
  fontWeight(v: number | FontWeight): ButtonAttribute; opacity(v: number): ButtonAttribute;
  scale(v: { x: number; y: number }): ButtonAttribute;
  animation(v: { duration: number; curve: Curve }): ButtonAttribute;
  backgroundColor(v: ResourceColor): ButtonAttribute; fontColor(v: ResourceColor): ButtonAttribute;
}
