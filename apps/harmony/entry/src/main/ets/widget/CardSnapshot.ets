/*
 * 服务卡片（契约 §17.c、§11 小组件同规则；对照 Android ZephyrWidget）的数据快照。
 * - UI 进程（CardSync）在连接状态变化时立即写、连接期间至多每 60 s 写一次；卡片进程（ZephyrFormAbility）只读文件，
 *   不加载引擎。快照里没有每秒变化的值（不显示实时速率，Android 评审 W-P1-1：冻结的 “2.8 MB/s” 会误导几个小时）。
 * - 文案在 UI 进程按当前语言格式化好再写入；零点刷新时日期变了，卡片进程把“今日”换成 todayZero（§11 / E44）。
 * 纯逻辑，无系统 API，便于 node / ohosTest 测试。
 */
export const CARD_SNAPSHOT_FILE: string = 'card-snapshot.json';
export const CARD_FORMS_FILE: string = 'card-forms.json';
/** 连接期间卡片刷新的最短间隔（同 Android LIVE_REFRESH_MS）。 */
export const CARD_LIVE_REFRESH_MS: number = 60000;
/** 中卡（2×4）最多显示的场景行（同 Android widgetFit 上限）。 */
export const CARD_SCENE_ROWS: number = 3;
/** 卡片点击带给 EntryAbility 的 Want 参数名：'toggle' = 电源按钮，'open' = 卡片其余区域。 */
export const CARD_ACTION_PARAM: string = 'zephyrCard';

export class CardScene {
  name: string = '';
  exit: string = '';
  ms: string = '';
}

export class CardSnapshot {
  on: boolean = false;
  busy: boolean = false;
  title: string = 'Zephyr';
  detail: string = '';
  today: string = '';
  todayZero: string = '';
  /** 写入时的本地日期 yyyy-mm-dd；与卡片刷新时的日期不同则显示 todayZero。 */
  day: string = '';
  scenesTitle: string = '';
  toggleLabel: string = '';
  scenes: CardScene[] = [];
}

export class CardSnapshots {
  static dayKey(at: number): string {
    const d = new Date(at);
    const p = (n: number): string => (n < 10 ? '0' : '') + n;
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
  }

  static encode(s: CardSnapshot): string {
    return JSON.stringify(s);
  }

  /** 坏文件 / 缺字段一律回到默认（未连接），卡片不因一次写坏而空白。 */
  static decode(text: string | undefined): CardSnapshot {
    const out = new CardSnapshot();
    if (text === undefined || text.length === 0) {
      return out;
    }
    try {
      const o = JSON.parse(text) as Record<string, Object>;
      out.on = o['on'] === true;
      out.busy = o['busy'] === true;
      out.title = typeof o['title'] === 'string' ? o['title'] as string : out.title;
      out.detail = typeof o['detail'] === 'string' ? o['detail'] as string : '';
      out.today = typeof o['today'] === 'string' ? o['today'] as string : '';
      out.todayZero = typeof o['todayZero'] === 'string' ? o['todayZero'] as string : '';
      out.day = typeof o['day'] === 'string' ? o['day'] as string : '';
      out.scenesTitle = typeof o['scenesTitle'] === 'string' ? o['scenesTitle'] as string : '';
      out.toggleLabel = typeof o['toggleLabel'] === 'string' ? o['toggleLabel'] as string : '';
      const sc = o['scenes'];
      if (Array.isArray(sc)) {
        (sc as Record<string, Object>[]).slice(0, CARD_SCENE_ROWS).forEach((r: Record<string, Object>) => {
          const c = new CardScene();
          c.name = typeof r['name'] === 'string' ? r['name'] as string : '';
          c.exit = typeof r['exit'] === 'string' ? r['exit'] as string : '';
          c.ms = typeof r['ms'] === 'string' ? r['ms'] as string : '';
          out.scenes.push(c);
        });
      }
    } catch (e) {
      return new CardSnapshot();
    }
    return out;
  }

  /** 卡片要显示的值：过了零点“今日”归零。 */
  static forDisplay(s: CardSnapshot, now: number): CardSnapshot {
    if (s.day.length > 0 && s.day !== CardSnapshots.dayKey(now) && s.todayZero.length > 0) {
      const c = CardSnapshots.decode(CardSnapshots.encode(s));
      c.today = c.todayZero;
      return c;
    }
    return s;
  }

  /** 卡片 LocalStorage 的键值（formBindingData）。wide = 2×4 卡（卡片页面不支持 onAreaChange，尺寸由提供方告知）。 */
  static binding(s: CardSnapshot, wide: boolean): Record<string, Object> {
    const r: Record<string, Object> = {
      'wide': wide,
      'on': s.on,
      'busy': s.busy,
      'title': s.title,
      'detail': s.detail,
      'today': s.today,
      'scenesTitle': s.scenesTitle,
      'toggleLabel': s.toggleLabel,
      'scenes': s.scenes
    };
    return r;
  }

  /** 已添加的卡片 id 列表（文件内容 → 数组），去重。 */
  static decodeIds(text: string | undefined): string[] {
    if (text === undefined || text.length === 0) {
      return [];
    }
    try {
      const a = JSON.parse(text) as Object;
      if (!Array.isArray(a)) {
        return [];
      }
      const out: string[] = [];
      (a as Object[]).forEach((x: Object) => {
        if (typeof x === 'string' && !out.includes(x as string)) {
          out.push(x as string);
        }
      });
      return out;
    } catch (e) {
      return [];
    }
  }

  /** 记录项 = 卡片 id + '#w'（2×4）或 '#s'（2×2）。 */
  static entry(id: string, wide: boolean): string {
    return id + (wide ? '#w' : '#s');
  }

  static idOf(entry: string): string {
    const i = entry.lastIndexOf('#');
    return i >= 0 ? entry.substring(0, i) : entry;
  }

  static isWide(entry: string): boolean {
    return entry.endsWith('#w');
  }

  /** 该卡片是否 2×4；没记录时按小卡。 */
  static wideOf(entries: string[], id: string): boolean {
    const e = entries.find((x: string) => CardSnapshots.idOf(x) === id);
    return e !== undefined && CardSnapshots.isWide(e);
  }

  static withId(entries: string[], id: string, wide: boolean): string[] {
    return CardSnapshots.withoutId(entries, id).concat([CardSnapshots.entry(id, wide)]);
  }

  static withoutId(entries: string[], id: string): string[] {
    return entries.filter((x: string) => CardSnapshots.idOf(x) !== id);
  }
}
