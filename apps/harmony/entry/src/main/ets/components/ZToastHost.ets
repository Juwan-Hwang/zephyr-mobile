/*
 * 吐司宿主：由根页面挂进 OverlayManager 浮层（窗口根，盖在 Navigation / 子页之上；失败时退回根 Stack），显示 AppServices.toasts 的当前吐司（§16.e⑥）。
 * - 出现时朗读文案（有撤销时连同“撤销”）；吐司获得读屏焦点期间不消失（ToastCenter.setFocused）。
 * - 撤销按钮用强调色，只执行撤销（ToastCenter.undoCurrent）；点文案关闭（提交）。整行不挂点按，以免抢走撤销。
 */
import { accessibility } from '@kit.AccessibilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppServices } from '../app/AppServices';
import { ToastState } from '../app/ToastCenter';
import { ZTheme } from '../common/Theme';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

@ComponentV2
export struct ZToastHost {
  /** 吐司离宿主底边的距离（vp）。 */
  @Param bottom: number = 72;
  @Local toast: ToastState | undefined = undefined;
  @Local theme: ZTheme = ZTheme.shared();
  private sub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    this.sub = AppServices.get().toasts.current.subscribe((t: ToastState | undefined) => {
      this.toast = t;
      if (t !== undefined) {
        hilog.info(0x5A50, 'ZToastHost', 'show #%{public}d undoable=%{public}s', t.serial, String(t.undoable));
        this.announce(t);
      }
    });
  }

  aboutToDisappear(): void {
    if (this.sub !== undefined) {
      this.sub.cancel();
      this.sub = undefined;
    }
  }

  private announce(t: ToastState): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined || !accessibility.isScreenReaderOpenSync()) {
        return;
      }
      let text = t.message;
      if (t.undoable) {
        text += ' ' + ctx.resourceManager.getStringSync(ZTerm.undo.id);
      }
      const ev = new accessibility.EventInfo({
        type: 'announceForAccessibility',
        bundleName: ctx.applicationInfo.name,
        triggerAction: 'common',
        textAnnouncedForAccessibility: text
      } as accessibility.EventInfo);
      accessibility.sendAccessibilityEvent(ev).catch(() => {});
    } catch (e) {
      // 朗读失败不影响吐司本身。
    }
  }

  build() {
    Column() {
      if (this.toast !== undefined) {
        Row({ space: 12 }) {
          // 点文案关闭（提交）；不再挂在整行上，免得行级点按抢在“撤销”之前把吐司提交掉（真机：点撤销只关闭不撤销）。
          Text(this.toast.message)
            .fontSize(15)
            .fontColor($r('app.color.screen_on_primary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ minHeight: 48 })
            .onClick(() => {
              const t = this.toast;
              if (t !== undefined) {
                AppServices.get().toasts.dismiss(t.serial);
              }
            })
          if (this.toast.undoable) {
            Text(ZTerm.undo)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.accentColor())
              .padding({ left: 8, right: 8, top: 10, bottom: 10 })
              .accessibilityRole(AccessibilityRoleType.BUTTON)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                // 撤销“当前”吐司：不用本组件缓存的 serial（浮层里的 @Local 可能滞后于 ToastCenter）。
                const done = AppServices.get().toasts.undoCurrent();
                hilog.info(0x5A50, 'ZToastHost', 'undo tapped, ran=%{public}s', String(done));
              })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 8 })
        .borderRadius(14)
        .backgroundColor($r('app.color.screen_primary'))
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        // 卡片本身挡住下面的页面（点内边距不漏给底下），但不挂点按手势。
        .hitTestBehavior(HitTestMode.Block)
        .onAccessibilityFocus((focused: boolean) => {
          const t = this.toast;
          if (t !== undefined) {
            AppServices.get().toasts.setFocused(t.serial, focused);
          }
        })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 })).animation({ duration: 200 }))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: this.toast !== undefined ? this.bottom : 0 })
    // 自身不吃触摸（没有吐司时不挡首页底栏 / 页面）；吐司卡片本身照常可点，且不会把点按漏给下面的页面。
    .hitTestBehavior(HitTestMode.None)
  }
}
