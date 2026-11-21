import { describe, expect, it } from '@ohos/hypium';
import {
  AppNav, BackTo, LibraryDest, NavArgs, ROUTE_LICENSES, ROUTE_LOGS, ROUTE_NODES, ROUTE_RULES, ROUTE_SETTINGS,
  ROUTE_SUBSCRIPTIONS
} from '../../../main/ets/app/AppNav';
import { GestureLock } from '../../../main/ets/common/GestureLock';

/* 契约 §17.e：无底部 Tab；资料库入口 → 二级页，从资料库进的页面返回首页时重开资料库；外链导入不重复叠订阅页。 */

export default function navTest(): void {
  describe('AppNav', () => {
    it('library destinations map to routes', 0, () => {
      expect(AppNav.routeOf(LibraryDest.NODES)).assertEqual(ROUTE_NODES);
      expect(AppNav.routeOf(LibraryDest.SUBSCRIPTIONS)).assertEqual(ROUTE_SUBSCRIPTIONS);
      expect(AppNav.routeOf(LibraryDest.RULES)).assertEqual(ROUTE_RULES);
      expect(AppNav.routeOf(LibraryDest.SETTINGS)).assertEqual(ROUTE_SETTINGS);
      expect(AppNav.routeOf(LibraryDest.SCENES)).assertEqual('');
      const all: string[] = [ROUTE_NODES, ROUTE_SUBSCRIPTIONS, ROUTE_RULES, ROUTE_SETTINGS, ROUTE_LOGS, ROUTE_LICENSES];
      for (const r of all) {
        expect(AppNav.isRoute(r)).assertTrue();
      }
      expect(AppNav.isRoute('home')).assertFalse();
    });

    it('reopens library only when popping back home from a library page', 0, () => {
      expect(AppNav.backOf(new NavArgs(BackTo.LIBRARY))).assertEqual(BackTo.LIBRARY);
      expect(AppNav.backOf(undefined)).assertUndefined();
      expect(AppNav.reopenLibraryAfterPop(BackTo.LIBRARY, true)).assertTrue();
      expect(AppNav.reopenLibraryAfterPop(BackTo.LIBRARY, false)).assertFalse();
      expect(AppNav.reopenLibraryAfterPop(BackTo.HOME, true)).assertFalse();
      expect(AppNav.reopenLibraryAfterPop(BackTo.PARENT, true)).assertFalse();
      expect(AppNav.reopenLibraryAfterPop(undefined, true)).assertFalse();
    });

    it('import pushes subscriptions once', 0, () => {
      expect(AppNav.shouldPushSubscriptionsForImport('')).assertTrue();
      expect(AppNav.shouldPushSubscriptionsForImport(ROUTE_SETTINGS)).assertTrue();
      expect(AppNav.shouldPushSubscriptionsForImport(ROUTE_SUBSCRIPTIONS)).assertFalse();
    });

    it('gesture lock holds through grace period', 0, () => {
      GestureLock.hold();
      expect(GestureLock.active()).assertTrue();
      GestureLock.release();
      expect(GestureLock.active()).assertTrue();
      expect(GestureLock.active(Date.now() + 400)).assertFalse();
    });
  });
}
