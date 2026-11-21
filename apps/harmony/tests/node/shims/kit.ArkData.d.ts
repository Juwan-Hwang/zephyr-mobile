import { common } from './kit.AbilityKit';
export namespace preferences {
  type ValueType = number | string | boolean | Array<number> | Array<string> | Array<boolean>;
  interface Options { name: string; dataGroupId?: string }
  interface Preferences {
    get(key: string, defValue: ValueType): Promise<ValueType>;
    put(key: string, value: ValueType): Promise<void>;
    flush(): Promise<void>;
  }
  function getPreferences(context: common.Context, options: Options): Promise<Preferences>;
}
