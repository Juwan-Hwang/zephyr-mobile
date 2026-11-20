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

const ROUTE_LOGS: string = 'logs';
const ROUTE_LICENSES: string = 'licenses';

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

  aboutToAppear(): void {
    this.inboxSub = ImportInbox.stream().subscribe((r: ImportRequest | undefined) => {
      if (r !== undefined) {
        this.select(TAB_LIBRARY);
      }
    });
  }

  aboutToDisappear(): void {
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
      ZToastHost()
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
