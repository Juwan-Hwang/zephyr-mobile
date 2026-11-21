/*
 * 根页面：Navigation（栈模式，子页面 logs / licenses）包着底部 Tabs：首页 / 节点 / 资料库（订阅 + 规则）/ 设置。
 * 外链导入请求到达（ImportInbox）时切到资料库，由订阅页出确认面板。
 * 状态管理统一用 V2（@ComponentV2 / @Local / @Param / @Event），引擎流在 aboutToAppear 订阅、aboutToDisappear 取消。
 */
import { ImportInbox } from '../app/ImportInbox';
import { ImportRequest } from '../entryability/DeepLink';
import { Subscription as StreamSub } from '../engine/Stream';
import { HomeView } from '../views/HomeView';
import { NodesView } from '../views/NodesView';
import { LibraryView } from '../views/LibraryView';
import { SettingsView } from '../views/SettingsView';
import { LogsPage } from './LogsPage';
import { LicensesPage } from './LicensesPage';
import { ZTerm } from '../generated/ZTerms';
import { ZTheme } from '../common/Theme';
import { ZToastHost } from '../components/ZToastHost';
import { ComponentContent, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const ROUTE_LOGS: string = 'logs';
const ROUTE_LICENSES: string = 'licenses';

const TAB_BAR_HEIGHT: number = 56;
const TOAST_GAP: number = 16;

/** 吐司浮层参数：离窗口底边的距离（tab 栏 + 底部导航条 + 间距）。 */
class ToastLayerArgs {
  bottom: number;

  constructor(bottom: number) {
    this.bottom = bottom;
  }
}

/**
 * 吐司浮层（OverlayManager，renderRootOverlay 默认 true）：挂在窗口根上，盖在 Navigation / 子页 / Tabs 之上，
 * 所以在任何页面（含 logs / licenses 子页）删除后都看得见。根节点 HitTestMode.None：自身不吃触摸，只有吐司卡片可点。
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

const TAB_HOME: number = 0;
const TAB_NODES: number = 1;
const TAB_LIBRARY: number = 2;
const TAB_SETTINGS: number = 3;

@Entry
@ComponentV2
struct Index {
  @Local tab: number = TAB_HOME;
  @Local theme: ZTheme = ZTheme.shared();
  private pathStack: NavPathStack = new NavPathStack();
  private tabs: TabsController = new TabsController();
  private inboxSub: StreamSub | undefined = undefined;
  /** OverlayManager 挂载失败时退回页面内 Stack 宿主。 */
  @Local inlineToast: boolean = false;
  private toastContent: ComponentContent<ToastLayerArgs> | undefined = undefined;

  aboutToAppear(): void {
    this.inboxSub = ImportInbox.stream().subscribe((r: ImportRequest | undefined) => {
      if (r !== undefined) {
        this.select(TAB_LIBRARY);
      }
    });
  }

  onDidBuild(): void {
    this.mountToastLayer();
  }

  /** 底部导航条高度（vp）+ tab 栏 + 间距；取不到导航条时按 0。 */
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
    return TAB_BAR_HEIGHT + TOAST_GAP + indicator;
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

  private select(i: number): void {
    this.tab = i;
    this.tabs.changeIndex(i);
  }

  @Builder
  tabBar(index: number, label: ResourceStr) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.tab === index ? $r('app.color.screen_t1') : $r('app.color.screen_t3'))
      Divider()
        .width(16)
        .strokeWidth(2)
        .color(this.tab === index ? this.theme.accentColor() : Color.Transparent)
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  routes(name: string, param: Object) {
    if (name === ROUTE_LOGS) {
      LogsPage()
    } else if (name === ROUTE_LICENSES) {
      LicensesPage()
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.navigation()
      if (this.inlineToast) {
        ZToastHost({ bottom: TAB_BAR_HEIGHT + TOAST_GAP })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navigation() {
    Navigation(this.pathStack) {
      Tabs({ barPosition: BarPosition.End, index: this.tab, controller: this.tabs }) {
        TabContent() {
          HomeView({
            onOpenNodes: () => this.select(TAB_NODES),
            onOpenLibrary: () => this.select(TAB_LIBRARY)
          })
        }
        .tabBar(this.tabBar(TAB_HOME, $r('app.string.common_home')))

        TabContent() {
          NodesView({ onImport: () => this.select(TAB_LIBRARY) })
        }
        .tabBar(this.tabBar(TAB_NODES, ZTerm.nodes))

        TabContent() {
          LibraryView()
        }
        .tabBar(this.tabBar(TAB_LIBRARY, $r('app.string.common_library')))

        TabContent() {
          SettingsView({
            onOpenLogs: () => this.pathStack.pushPathByName(ROUTE_LOGS, ''),
            onOpenLicenses: () => this.pathStack.pushPathByName(ROUTE_LICENSES, '')
          })
        }
        .tabBar(this.tabBar(TAB_SETTINGS, ZTerm.settings))
      }
      .scrollable(false)
      .animationDuration(0)
      .barHeight(56)
      .barBackgroundColor($r('app.color.screen_glass'))
      .onChange((i: number) => {
        this.tab = i;
      })
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .navDestination(this.routes)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
