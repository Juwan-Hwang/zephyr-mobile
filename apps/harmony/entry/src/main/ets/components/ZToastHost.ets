/*
 * 吐司宿主：放在根页面底部，显示 AppServices.toasts 的当前吐司（§16.e⑥）。
 * - 出现时朗读文案（有撤销时连同“撤销”）；吐司获得读屏焦点期间不消失（ToastCenter.setFocused）。
 * - 撤销按钮用强调色；点吐司本身关闭（提交）。
 */
import { accessibility } from '@kit.AccessibilityKit';
import { AppServices } from '../app/AppServices';
import { ToastState } from '../app/ToastCenter';
import { ZTheme } from '../common/Theme';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

@ComponentV2
export struct ZToastHost {
  @Local toast: ToastState | undefined = undefined;
  @Local theme: ZTheme = ZTheme.shared();
  private sub: StreamSub | undefined = undefined;

  aboutToAppear(): void {
    this.sub = AppServices.get().toasts.current.subscribe((t: ToastState | undefined) => {
      this.toast = t;
      if (t !== undefined) {
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
          Text(this.toast.message)
            .fontSize(15)
            .fontColor($r('app.color.screen_on_primary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.toast.undoable) {
            Text(ZTerm.undo)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.accentColor())
              .padding({ left: 8, right: 8, top: 10, bottom: 10 })
              .accessibilityRole(AccessibilityRoleType.BUTTON)
              .onClick(() => {
                const t = this.toast;
                if (t !== undefined) {
                  AppServices.get().toasts.undo(t.serial);
                }
              })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 8 })
        .borderRadius(14)
        .backgroundColor($r('app.color.screen_primary'))
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .onAccessibilityFocus((focused: boolean) => {
          const t = this.toast;
          if (t !== undefined) {
            AppServices.get().toasts.setFocused(t.serial, focused);
          }
        })
        .onClick(() => {
          const t = this.toast;
          if (t !== undefined) {
            AppServices.get().toasts.dismiss(t.serial);
          }
        })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 })).animation({ duration: 200 }))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 72 })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
