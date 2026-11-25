import { LengthMetrics } from '@kit.ArkUI';
import { ZBtn } from '../common/ZButtonMods';
/*
 * 首次引导（M1-16；对照 Android ui/onboarding OnboardingScreen，原型 ob1 / ob2）：两步。
 * 1 / 2 添加订阅：粘贴链接输入框 + 粘贴（PasteButton 安全控件）+ 添加，扫码 / 从文件导入；导入路径同订阅页（SubscriptionImport），
 *   失败显示原因；导入中可取消（只是不再等结果，同 iOS #99）。
 * 2 / 2 选择方式：“已添加 X” + 简单 / 优选（单选卡，默认优选）+ 继续；系统返回回到第 1 步。
 * 继续：先写场景来源（Onboarding.applyMode），再记 onboarded，最后 onDone。
 */
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { AppServices } from '../app/AppServices';
import { ImportPickers, PickError, PickResult } from '../app/ImportPickers';
import { Onboarding } from '../app/Onboarding';
import { ImportOutcome, SubscriptionImport } from '../app/SubscriptionImport';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { ZNavRow } from '../components/ZNavRow';
import { ZSection } from '../components/ZSection';
import { ImportSource } from '../engine/Model';
import { ZTerm } from '../generated/ZTerms';

export const ONBOARDING_LINK_ID: string = 'zephyr.onboarding.link';
export const ONBOARDING_ADD_ID: string = 'zephyr.onboarding.add';
export const ONBOARDING_CONTINUE_ID: string = 'zephyr.onboarding.continue';
export const ONBOARDING_SIMPLE_ID: string = 'zephyr.onboarding.simple';
export const ONBOARDING_OPTIMIZED_ID: string = 'zephyr.onboarding.optimized';

@ComponentV2
export struct OnboardingView {
  @Event onDone: () => void = () => {};
  @Local step: number = 0;
  @Local link: string = '';
  @Local busy: boolean = false;
  @Local error: ResourceStr | undefined = undefined;
  @Local addedName: string = '';
  @Local addedNodes: number = 0;
  /** 0 = 简单，1 = 优选（默认）。 */
  @Local mode: number = 1;
  @Local saving: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  /** 每次导入递增；取消或新导入后，旧结果作废。 */
  private ticket: number = 0;

  aboutToAppear(): void {
    // 组件收不到 onBackPress：由 Index 转过来（第 2 步返回第 1 步，L-P2-11）。
    Onboarding.backHandler = (): boolean => {
      if (this.step === 1) {
        this.step = 0;
        return true;
      }
      return false;
    };
  }

  aboutToDisappear(): void {
    Onboarding.backHandler = undefined;
    this.ticket++;
  }

  private submit(source: ImportSource, text: string): void {
    if (this.busy || text.trim().length === 0) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    const t = ++this.ticket;
    SubscriptionImport.importText(AppServices.get().engine, source, text).then((o: ImportOutcome) => {
      if (t !== this.ticket) {
        return;
      }
      if (o.added > 0 && o.first !== undefined) {
        this.addedName = o.first.name;
        this.addedNodes = o.first.nodeCount;
        this.link = '';
        this.step = 1;
      } else if (o.error !== undefined) {
        this.error = Labels.importError(o.error, source === ImportSource.FILE);
      }
    }).finally(() => {
      if (t === this.ticket) {
        this.busy = false;
      }
    });
  }

  private cancelImport(): void {
    this.ticket++;
    this.busy = false;
  }

  private paste(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      const text = data.getRecordCount() > 0 ? data.getPrimaryText() : '';
      if (text === undefined || text.trim().length === 0) {
        this.error = $r('app.string.subs_error_clipboard_empty');
        return;
      }
      this.link = text.trim();
      this.submit(ImportSource.CLIPBOARD, text);
    }).catch((e: BusinessError) => {
      this.error = $r('app.string.subs_error_clipboard_empty');
    });
  }

  private scan(): void {
    const ctx = this.getUIContext().getHostContext();
    if (this.busy || ctx === undefined) {
      return;
    }
    this.error = undefined;
    ImportPickers.scanQr(ctx).then((r: PickResult) => {
      if (r.text !== undefined) {
        this.submit(ImportSource.QR, r.text);
      } else if (r.error === PickError.UNAVAILABLE) {
        this.error = $r('app.string.subs_scan_no_camera');
      }
    });
  }

  private pickFile(): void {
    const ctx = this.getUIContext().getHostContext();
    if (this.busy || ctx === undefined) {
      return;
    }
    this.error = undefined;
    ImportPickers.pickFile(ctx).then((r: PickResult) => {
      if (r.text !== undefined) {
        this.submit(ImportSource.FILE, r.text);
      } else if (r.error === PickError.UNREADABLE) {
        this.error = $r('app.string.subs_error_read_file');
      }
    });
  }

  private finish(): void {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const svc = AppServices.get();
    Onboarding.applyMode(svc.engine, this.mode === 0).catch(() => 0).then(() => svc.settings.setOnboarded())
      .finally(() => {
        this.saving = false;
        this.onDone();
      });
  }

  @Builder
  choice(id: string, title: Resource, body: Resource, selected: boolean, index: number) {
    Row({ space: 14 }) {
      Circle()
        .width(22)
        .height(22)
        .fill(Color.Transparent)
        .stroke(selected ? this.theme.accentColor() : $r('app.color.screen_t4'))
        .strokeWidth(selected ? 7 : 1.5)
        .margin({ top: 1 })
      Column({ space: 6 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
        Text(body)
          .fontSize(15)
          .fontColor($r('app.color.screen_t2'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .id(id)
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(18)
    .borderRadius(24)
    .backgroundColor(selected ? '#12' + this.theme.accentColor().substring(3) : $r('app.color.screen_s1'))
    .border({ width: 1, color: selected ? this.theme.accentColor() : $r('app.color.screen_hl') })
    .accessibilityRole(AccessibilityRoleType.RADIO)
    .accessibilityChecked(selected)
    .onClick(() => {
      this.mode = index;
    })
  }

  @Builder
  stepAdd() {
    Column({ space: 16 }) {
      Text($r('app.string.subs_add'))
        .fontSize(34)
        .fontWeight(FontWeight.Lighter)
        .lineHeight(40)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 6, right: 6 })
      TextInput({ text: this.link, placeholder: $r('app.string.subs_paste_placeholder') })
        .id(ONBOARDING_LINK_ID)
        .height(44)
        .fontSize(15)
        .backgroundColor($r('app.color.screen_s2'))
        .fontColor($r('app.color.screen_t1'))
        .type(InputType.URL)
        .enterKeyType(EnterKeyType.Done)
        .onChange((v: string) => {
          this.link = v;
          this.error = undefined;
        })
        .onSubmit(() => this.submit(ImportSource.URL, this.link))
      Row({ space: 8 }) {
        PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
          .fontSize(14)
          .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) {
              this.paste();
            }
          })
        Blank()
        if (this.busy) {
          Button($r('app.string.common_cancel'))
            .attributeModifier(ZBtn.ghost(this.theme.accentColor()))
            .accessibilityText($r('app.string.onboarding_cancel_import_a11y'))
            .onClick(() => this.cancelImport())
        }
        Button(this.busy ? $r('app.string.common_adding') : $r('app.string.common_add'))
          .attributeModifier(ZBtn.accentFill(this.theme.accentColor()))
          .id(ONBOARDING_ADD_ID)
          .enabled(!this.busy && this.link.trim().length > 0)
          .onClick(() => this.submit(ImportSource.URL, this.link))
      }
      .width('100%')
      ZSection() {
        ZNavRow({ title: $r('app.string.subs_scan_qr'), onTap: () => this.scan() })
        ZNavRow({ title: $r('app.string.subs_import_desktop'), onTap: () => this.scan() })
        ZNavRow({ title: ZTerm.importFromFile, divider: false, onTap: () => this.pickFile() })
      }
      if (this.error !== undefined) {
        Text(this.error)
          .fontSize(13)
          .fontColor($r('app.color.screen_red_text'))
          .padding({ left: 6, right: 6 })
      }
      Text($r('app.string.common_local_data_note'))
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
        .padding({ left: 6, right: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepMode() {
    Column({ space: 12 }) {
      Text($r('app.plural.subs_added', this.addedNodes, this.addedName, Format.grouped(this.addedNodes)))
        .fontSize(15)
        .fontColor($r('app.color.screen_green_text'))
        .padding({ left: 6, right: 6 })
      Text($r('app.string.onboarding_choose_mode'))
        .fontSize(34)
        .fontWeight(FontWeight.Lighter)
        .lineHeight(40)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 6, right: 6, bottom: 4 })
      this.choice(ONBOARDING_SIMPLE_ID, $r('app.string.onboarding_simple'), $r('app.string.onboarding_simple_desc'),
        this.mode === 0, 0)
      this.choice(ONBOARDING_OPTIMIZED_ID, $r('app.string.onboarding_optimized'),
        $r('app.string.onboarding_optimized_desc'), this.mode === 1, 1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Text('Zephyr')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.screen_t1'))
        .padding({ start: LengthMetrics.vp(6) })
      Text(`${this.step + 1} / 2`)
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
        .padding({ start: LengthMetrics.vp(6), top: LengthMetrics.vp(28), bottom: LengthMetrics.vp(8) })
      Scroll() {
        Column() {
          if (this.step === 0) {
            this.stepAdd()
          } else {
            this.stepMode()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      if (this.step === 1) {
        Button($r('app.string.onboarding_continue'))
          .attributeModifier(ZBtn.accentFill(this.theme.accentColor(), true))
          .id(ONBOARDING_CONTINUE_ID)
          .width('100%')
          .enabled(!this.saving)
          .onClick(() => this.finish())
        Text($r('app.string.onboarding_change_later'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
          .padding(12)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 24, bottom: 16 })
    .backgroundColor($r('app.color.screen_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
