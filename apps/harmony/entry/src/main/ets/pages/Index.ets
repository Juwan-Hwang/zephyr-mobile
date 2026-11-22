/*
 * 根页面（契约 §17.e：同 iOS RootView / Android AppRoot 与原型，没有底部 Tab）：
 * - Navigation（栈模式）：navBar = 首页；二级页 节点 / 订阅 / 规则 / 设置 / 日志 / 开源许可 为 NavDestination，
 *   系统返回键与侧滑返回由 Navigation 出栈，到首页后再返回则退出（交给系统）。
 * - 资料库：首页底部资料库按钮打开 bindSheet（中 / 大两档）；点入口收起 sheet 再 push，返回时重开资料库（AppNav）。
 * - 首页右上设置、“当前节点”卡、外链导入（ImportInbox → 订阅页确认卡）直接 push，返回首页。
 * - 吐司：窗口级 OverlayManager 浮层（盖在 Navigation / 子页 / sheet 之上），失败时退回根 Stack 内联宿主。
 * - 首页场景行横滑期间（GestureLock）吞掉首页上的系统返回，免得滑动贴边时被当成返回退出 App。
 * 状态管理统一用 V2（@ComponentV2 / @Local / @Param / @Event），引擎流在 aboutToAppear 订阅、aboutToDisappear 取消。
 */
import { AppServices } from '../app/AppServices';
import { ImportInbox } from '../app/ImportInbox';
import {
  AppNav,
  BackTo,
  LibraryDest,
  NavArgs,
  ROUTE_LICENSES,
  ROUTE_LOGS,
  ROUTE_LOCAL_PROXY,
  ROUTE_TRUSTED_WIFI,
  ROUTE_NODES,
  ROUTE_RULES,
  ROUTE_SETTINGS,
  ROUTE_SUBSCRIPTIONS,
  ROUTE_TODAY
} from '../app/AppNav';
import { ImportRequest } from '../entryability/DeepLink';
import { Subscription as StreamSub } from '../engine/Stream';
import { HomeView } from '../views/HomeView';
import { NodesView } from '../views/NodesView';
import { SubscriptionsView } from '../views/SubscriptionsView';
import { RulesView } from '../views/RulesView';
import { SettingsView } from '../views/SettingsView';
import { LibrarySheet } from '../views/LibrarySheet';
import { LogsPage } from './LogsPage';
import { OnboardingView } from '../views/OnboardingView';
import { Onboarding } from '../app/Onboarding';
import { TrustedWifiPage } from './TrustedWifiPage';
import { LocalProxyPage } from './LocalProxyPage';
import { LicensesPage } from './LicensesPage';
import { TodayPage } from './TodayPage';
import { ZTerm } from '../generated/ZTerms';
import { ZToastHost } from '../components/ZToastHost';
import { GestureLock } from '../common/GestureLock';
import { ComponentContent, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 吐司离底边：首页底栏（52 + 上下 10）之上再留 12（同 Android padding(bottom = 84.dp)），另加导航条避让区。 */
const DOCK_CLEARANCE: number = 84;

/** 吐司浮层参数：离窗口底边的距离（底栏避让 + 底部导航条）。 */
class ToastLayerArgs {
  bottom: number;

  constructor(bottom: number) {
    this.bottom = bottom;
  }
}

/**
 * 吐司浮层（OverlayManager，renderRootOverlay 默认 true）：挂在窗口根上，盖在 Navigation / 子页 / sheet 之上，
 * 所以在任何页面删除后都看得见。根节点 HitTestMode.None：自身不吃触摸，只有吐司卡片可点。
 */
@Builder
function toastLayer(args: ToastLayerArgs) {
  Column() {
    ZToastHost({ bottom: args.bottom })
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.End)
  .hitTestBehavior(HitTestMode.None)
}

@Entry
@ComponentV2
struct Index {
  @Local showLibrary: boolean = false;
  /** 首次引导（M1-16）：在屏时替换整个导航。 */
  @Local onboarding: boolean = false;
  private onboardingSub: StreamSub | undefined = undefined;
  /** 资料库“场景”入口：资料库收起后递增，首页打开第一个场景的 sheet（M1-5）。 */
  @Local sceneRequest: number = 0;
  private sceneAfterLibrary: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private inboxSub: StreamSub | undefined = undefined;
  /** OverlayManager 挂载失败时退回页面内 Stack 宿主。 */
  @Local inlineToast: boolean = false;
  private toastContent: ComponentContent<ToastLayerArgs> | undefined = undefined;

  aboutToAppear(): void {
    this.pathStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar, op: NavigationOperation,
        animated: boolean) => this.didShow(from, to, op)
    });
    const svc = AppServices.get();
    svc.settings.onboarded().then((done: boolean) => {
      if (Onboarding.shouldShow(svc.engine.kind, done)) {
        this.onboarding = true;
      }
    });
    this.onboardingSub = Onboarding.request.subscribe((n: number) => {
      if (n > 0) {
        this.pathStack.clear(false);
        this.showLibrary = false;
        this.onboarding = true;
      }
    });
    this.inboxSub = ImportInbox.stream().subscribe((r: ImportRequest | undefined) => {
      if (r !== undefined) {
        this.openForImport();
      }
    });
  }

  onDidBuild(): void {
    this.mountToastLayer();
  }

  /** 首页场景行横滑期间吞掉系统返回（栈空时返回会退出 App）；子页的返回照常交给 Navigation。 */
  onBackPress(): boolean | void {
    if (this.onboarding) {
      const h = Onboarding.backHandler;
      return h !== undefined ? h() : false;
    }
    if (this.pathStack.size() === 0 && GestureLock.active()) {
      hilog.warn(0x5A50, 'Index', 'back blocked during scene-row swipe');
      return true;
    }
    return false;
  }

  /** 出栈回到首页、离开的页面来自资料库 → 重开资料库（返回键 / 侧滑 / 标题栏返回都走这里）。 */
  private didShow(from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar, op: NavigationOperation): void {
    if (op !== NavigationOperation.POP || typeof from === 'string') {
      return;
    }
    const ctx = from as NavDestinationContext;
    const back = AppNav.backOf(ctx.pathInfo.param as Object);
    const toHome = typeof to === 'string';
    hilog.info(0x5A50, 'Index', 'pop %{public}s back=%{public}s toHome=%{public}s', ctx.pathInfo.name,
      String(back), String(toHome));
    if (AppNav.reopenLibraryAfterPop(back, toHome)) {
      this.showLibrary = true;
    }
  }

  private push(route: string, back: BackTo): void {
    this.pathStack.pushPathByName(route, new NavArgs(back));
  }

  private openFromLibrary(d: LibraryDest): void {
    this.showLibrary = false;
    if (d === LibraryDest.SCENES) {
      // 两个 sheet 不叠：等资料库 sheet 消失（onDisappear）再开场景 sheet。
      this.sceneAfterLibrary = true;
      return;
    }
    const route = AppNav.routeOf(d);
    if (route.length > 0) {
      this.push(route, BackTo.LIBRARY);
    }
  }

  /** 外链导入：收起资料库，订阅页不在栈顶就 push（订阅页出确认卡，从不自动导入）。 */
  private openForImport(): void {
    this.showLibrary = false;
    const names = this.pathStack.getAllPathName();
    const top = names.length > 0 ? names[names.length - 1] : '';
    if (AppNav.shouldPushSubscriptionsForImport(top)) {
      this.push(ROUTE_SUBSCRIPTIONS, BackTo.HOME);
    }
  }

  /** 底部导航条高度（vp）+ 底栏避让；取不到导航条时按 0。 */
  private async toastBottom(): Promise<number> {
    let indicator = 0;
    try {
      const ui = this.getUIContext();
      const ctx = ui.getHostContext();
      if (ctx !== undefined) {
        const win = await window.getLastWindow(ctx);
        const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        indicator = ui.px2vp(area.bottomRect.height);
      }
    } catch (e) {
      indicator = 0;
    }
    return DOCK_CLEARANCE + indicator;
  }

  private mountToastLayer(): void {
    if (this.toastContent !== undefined || this.inlineToast) {
      return;
    }
    const ui = this.getUIContext();
    this.toastBottom().then((bottom: number) => {
      try {
        const content = new ComponentContent<ToastLayerArgs>(ui, wrapBuilder<[ToastLayerArgs]>(toastLayer),
          new ToastLayerArgs(bottom));
        ui.getOverlayManager().addComponentContent(content);
        this.toastContent = content;
        hilog.info(0x5A50, 'Index', 'toast overlay mounted bottom=%{public}d', Math.round(bottom));
      } catch (e) {
        hilog.error(0x5A50, 'Index', 'toast overlay failed, inline host: %{public}s', String(e));
        this.inlineToast = true;
      }
    });
  }

  aboutToDisappear(): void {
    if (this.toastContent !== undefined) {
      try {
        this.getUIContext().getOverlayManager().removeComponentContent(this.toastContent);
        this.toastContent.dispose();
      } catch (e) {
        // 窗口已销毁。
      }
      this.toastContent = undefined;
    }
    if (this.inboxSub !== undefined) {
      this.inboxSub.cancel();
      this.inboxSub = undefined;
    }
  }

  @Builder
  routes(name: string, param: Object) {
    if (name === ROUTE_NODES) {
      NavDestination() {
        NodesView({
          initialQuery: AppNav.queryOf(param),
          onImport: () => this.push(ROUTE_SUBSCRIPTIONS, BackTo.PARENT)
        })
      }
      .title(ZTerm.nodes)
      .backgroundColor($r('app.color.screen_bg'))
    } else if (name === ROUTE_SUBSCRIPTIONS) {
      NavDestination() {
        SubscriptionsView()
      }
      .title(ZTerm.subscriptions)
      .backgroundColor($r('app.color.screen_bg'))
    } else if (name === ROUTE_RULES) {
      NavDestination() {
        RulesView()
      }
      .title(ZTerm.rules)
      .backgroundColor($r('app.color.screen_bg'))
    } else if (name === ROUTE_SETTINGS) {
      NavDestination() {
        SettingsView({
          onOpenLogs: () => this.push(ROUTE_LOGS, BackTo.PARENT),
          onOpenLicenses: () => this.push(ROUTE_LICENSES, BackTo.PARENT),
          onOpenTrustedWifi: () => this.push(ROUTE_TRUSTED_WIFI, BackTo.PARENT),
          onOpenLocalProxy: () => this.push(ROUTE_LOCAL_PROXY, BackTo.PARENT)
        })
      }
      .title(ZTerm.settings)
      .backgroundColor($r('app.color.screen_bg'))
    } else if (name === ROUTE_LOGS) {
      LogsPage()
    } else if (name === ROUTE_LICENSES) {
      LicensesPage()
    } else if (name === ROUTE_TRUSTED_WIFI) {
      TrustedWifiPage()
    } else if (name === ROUTE_LOCAL_PROXY) {
      LocalProxyPage()
    } else if (name === ROUTE_TODAY) {
      TodayPage()
    }
  }

  @Builder
  librarySheet() {
    LibrarySheet({ onOpen: (d: LibraryDest) => this.openFromLibrary(d) })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.onboarding) {
        OnboardingView({
          onDone: () => {
            this.onboarding = false;
          }
        })
      } else {
        this.navigation()
      }
      if (this.inlineToast) {
        ZToastHost({ bottom: DOCK_CLEARANCE })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navigation() {
    Navigation(this.pathStack) {
      HomeView({
        onOpenNodes: () => this.push(ROUTE_NODES, BackTo.HOME),
        onOpenLibrary: () => {
          this.showLibrary = true;
        },
        onOpenSettings: () => this.push(ROUTE_SETTINGS, BackTo.HOME),
        onOpenNodesQuery: (q: string) => this.pathStack.pushPathByName(ROUTE_NODES, new NavArgs(BackTo.HOME, q)),
        onOpenRules: () => this.push(ROUTE_RULES, BackTo.HOME),
        onOpenToday: () => this.push(ROUTE_TODAY, BackTo.HOME),
        onOpenSubscriptions: () => this.push(ROUTE_SUBSCRIPTIONS, BackTo.HOME),
        sceneRequest: this.sceneRequest
      })
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .navDestination(this.routes)
    .backgroundColor($r('app.color.screen_bg'))
    .bindSheet(this.showLibrary, this.librarySheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      title: { title: $r('app.string.common_library') },
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.screen_bg'),
      onDisappear: () => {
        this.showLibrary = false;
        if (this.sceneAfterLibrary) {
          this.sceneAfterLibrary = false;
          this.sceneRequest++;
        }
      }
    })
  }
}
