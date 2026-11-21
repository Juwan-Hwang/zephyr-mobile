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
