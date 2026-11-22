/*
 * 应用导航（契约 §17.e：同 iOS RootView / Android AppRoot 与原型，**没有底部 Tab**）：
 * 单一首页（Navigation 的 navBar）+ 资料库 sheet + 二级页（NavDestination）。
 * - 资料库 sheet：节点 / 订阅 / 规则 / 场景 四个统计入口 + 设置；点入口先收起 sheet 再 push 二级页。
 * - 从资料库进入的页面，返回（返回键 / 侧滑 / 标题栏返回）后重新打开资料库（Android BackTo.LIBRARY，原型 1287）；
 *   从首页进入的（首页“当前节点”卡、右上设置、外链导入）返回首页。
 * 本文件只放纯逻辑（路由名、参数、返回去向），页面装配在 pages/Index.ets，便于 ohosTest / node 单测。
 */

export const ROUTE_NODES: string = 'nodes';
export const ROUTE_SUBSCRIPTIONS: string = 'subscriptions';
export const ROUTE_RULES: string = 'rules';
export const ROUTE_SETTINGS: string = 'settings';
export const ROUTE_LOGS: string = 'logs';
export const ROUTE_LICENSES: string = 'licenses';
/** 设置里的受信任 Wi‑Fi / 本地代理端口（M1-14）。 */
export const ROUTE_TRUSTED_WIFI: string = 'trustedWifi';
export const ROUTE_LOCAL_PROXY: string = 'localProxy';
/** 今日卡（M1-9），首页流量卡“今日 X”进入。 */
export const ROUTE_TODAY: string = 'today';

/** 二级页返回到哪里（Android `BackTo`）。 */
export enum BackTo {
  HOME = 'home',
  LIBRARY = 'library',
  /** 设置里的子页（日志、开源许可）：返回设置页，不重开资料库。 */
  PARENT = 'parent'
}

/** 资料库 sheet 的入口（Android `LibraryDest`；受信任 Wi‑Fi / 本地代理在设置里进入，服务卡片页待 M1-19，见 §17.c）。 */
export enum LibraryDest {
  NODES = 'nodes',
  SUBSCRIPTIONS = 'subscriptions',
  RULES = 'rules',
  SCENES = 'scenes',
  SETTINGS = 'settings'
}

/** NavPathStack 的 param。 */
export class NavArgs {
  back: BackTo;
  /** 节点页的初始查询（指令面板“查看全部”，§16.d：查询 = 地区代码）。 */
  query: string;

  constructor(back: BackTo, query?: string) {
    this.back = back;
    this.query = query ?? '';
  }
}

export class AppNav {
  /** 资料库入口 → 路由名；场景没有独立页（收起资料库后由首页开场景 sheet，M1-5），返回 ''。 */
  static routeOf(d: LibraryDest): string {
    switch (d) {
      case LibraryDest.NODES:
        return ROUTE_NODES;
      case LibraryDest.SUBSCRIPTIONS:
        return ROUTE_SUBSCRIPTIONS;
      case LibraryDest.RULES:
        return ROUTE_RULES;
      case LibraryDest.SETTINGS:
        return ROUTE_SETTINGS;
      default:
        return '';
    }
  }

  /** 已知的二级页路由。 */
  static isRoute(name: string): boolean {
    return name === ROUTE_NODES || name === ROUTE_SUBSCRIPTIONS || name === ROUTE_RULES || name === ROUTE_SETTINGS ||
      name === ROUTE_LOGS || name === ROUTE_LICENSES || name === ROUTE_TODAY || name === ROUTE_TRUSTED_WIFI ||
      name === ROUTE_LOCAL_PROXY;
  }

  /**
   * 一次出栈之后是否要重开资料库：离开的页面是从资料库打开的，且回到了首页（navBar）。
   * fromBack 为离开页面的 NavArgs.back（取不到时 undefined），toHome 为目标是否 navBar。
   */
  static reopenLibraryAfterPop(fromBack: BackTo | undefined, toHome: boolean): boolean {
    return toHome && fromBack === BackTo.LIBRARY;
  }

  /** 从 NavPathInfo.param 取 back（param 可能是 NavArgs、旧的字符串或 undefined）。 */
  /** 节点页初始查询（无则 ''）。 */
  static queryOf(param: Object | undefined | null): string {
    if (param instanceof NavArgs) {
      return param.query;
    }
    return '';
  }

  static backOf(param: Object | undefined | null): BackTo | undefined {
    if (param instanceof NavArgs) {
      return param.back;
    }
    return undefined;
  }

  /**
   * 外链导入到达时要不要 push 订阅页：当前栈顶已是订阅页就不再叠一层（订阅页自己显示确认卡）。
   * topRoute 为栈顶路由名，空栈（在首页）传 ''。
   */
  static shouldPushSubscriptionsForImport(topRoute: string): boolean {
    return topRoute !== ROUTE_SUBSCRIPTIONS;
  }
}
