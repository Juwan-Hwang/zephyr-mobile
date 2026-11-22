import { LengthMetrics } from '@kit.ArkUI';
/*
 * 今日卡（M1-9 / U13，原型 today；对照 Android ui/today/TodayScreen.kt、iOS Activity/TodayCard*、WindArt）。
 * 首页流量卡“今日 X”点按进入（NavDestination，同 Android composable<Today>）。页面恒为黑底（审查 H-P2-13）。
 * - 卡片：流场图（Canvas，TodayArt，约 140 条线随 24 小时流量起伏；不含节点名与 IP）+ 日期、今日用量大字、
 *   地区数 / 在线小时 / 最快延迟、Zephyr 字标 + “今日”。
 * - 三配色：夜 / 晨 / 雾。
 * - 分享：componentSnapshot 取卡片 PixelMap → PNG 写入 cacheDir/share → systemShare（@kit.ShareKit）。
 * - 存储图像：SaveButton 安全控件（免存储权限，用户点按即授权；按钮文字为系统固定的“保存图片”）→ photoAccessHelper.createAsset 写 PNG；
 *   结果文案“已存储到相册 / 无法存储图像”替换脚注 3 秒（同 Android A-P1-3）。
 * 流场缓慢漂移（Android 可选项）未做：静态图与分享图一致。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppServices } from '../app/AppServices';
import { HapticKind, Haptics } from '../app/Haptics';
import { TODAY_ASPECT, TODAY_STRANDS, TODAY_STYLES, TodayArt, TodayPalette, TodayStats, TodayStyle } from '../app/TodayArt';
import { Format } from '../common/Format';
import { UsageSummary } from '../engine/Model';

const CARD_ID: string = 'zephyr-today-card';

@ComponentV2
export struct TodayPage {
  @Local usage: UsageSummary | undefined = undefined;
  @Local style: TodayStyle = TodayStyle.NIGHT;
  @Local saved: ResourceStr | undefined = undefined;
  @Local cardW: number = 0;
  @Local cardH: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx2d: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private savedTimer: number = -1;

  aboutToAppear(): void {
    AppServices.get().engine.usageToday().then((u: UsageSummary) => {
      this.usage = u;
      this.draw();
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.savedTimer >= 0) {
      clearTimeout(this.savedTimer);
      this.savedTimer = -1;
    }
  }

  private pal(): TodayPalette {
    return TodayArt.palette(this.style);
  }

  private draw(): void {
    const c = this.ctx2d;
    const w = c.width;
    const h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    const u = this.usage;
    if (u === undefined) {
      return;
    }
    const p = this.pal();
    c.lineWidth = 1.1;
    for (let s = 0; s < TODAY_STRANDS; s++) {
      const pts = TodayArt.strand(u.hourly, w, h, s, 0);
      c.beginPath();
      c.moveTo(pts[0], pts[1]);
      for (let i = 2; i < pts.length; i += 2) {
        c.lineTo(pts[i], pts[i + 1]);
      }
      c.strokeStyle = TodayArt.withAlpha(p.line, TodayArt.alpha(s));
      c.stroke();
    }
  }

  private dateText(): string {
    try {
      return new Intl.DateTimeFormat(undefined, { month: 'long', day: 'numeric', weekday: 'long' }).format(new Date());
    } catch (e) {
      return Format.date(Date.now());
    }
  }

  private flash(r: ResourceStr): void {
    this.saved = r;
    if (this.savedTimer >= 0) {
      clearTimeout(this.savedTimer);
    }
    this.savedTimer = setTimeout(() => {
      this.savedTimer = -1;
      this.saved = undefined;
    }, 3000);
  }

  /** 卡片 → PNG 字节。 */
  private async png(): Promise<ArrayBuffer> {
    const pm: image.PixelMap = await this.getUIContext().getComponentSnapshot().get(CARD_ID);
    const packer = image.createImagePacker();
    try {
      const opts: image.PackingOption = { format: 'image/png', quality: 100 };
      return await packer.packToData(pm, opts);
    } finally {
      packer.release();
      pm.release();
    }
  }

  private async share(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const data = await this.png();
    const dir = ctx.cacheDir + '/share';
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    const path = dir + '/zephyr-today.png';
    const f = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(f.fd, data);
    } finally {
      fileIo.closeSync(f);
    }
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PNG,
      uri: fileUri.getUriFromPath(path)
    };
    const controller = new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(ctx, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  private async save(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const data = await this.png();
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
    const f = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      await fileIo.write(f.fd, data);
    } finally {
      await fileIo.close(f);
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          Column() {
            this.card()
          }
          .width('100%')
          .padding({ left: 22, right: 22 })
          this.styles()
          this.actions()
          Text(this.saved ?? $r('app.string.today_pattern_note'))
            .width('100%')
            .padding(16)
            .textAlign(TextAlign.Center)
            .fontSize(12)
            .fontColor('#73FFFFFF')
        }
        .width('100%')
        .padding({ top: 8, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .title($r('app.string.term_today'))
    .backgroundColor(Color.Black)
    .systemBarStyle({ statusBarContentColor: '#FFFFFF' })
  }

  @Builder
  stat(v: string, label: ResourceStr, fg: string) {
    Column() {
      Text(v)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontFamily('monospace')
        .fontColor(fg)
      Text(label)
        .fontSize(12)
        .fontColor(TodayArt.withAlpha(fg, 0.55))
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  card() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Canvas(this.ctx2d)
        .width('100%')
        .height('100%')
        .onReady(() => this.draw())
        .onAreaChange(() => this.draw())
        .accessibilityLevel('no')
      Column() {
        Text(this.dateText())
          .fontSize(13)
          .fontColor(TodayArt.withAlpha(this.pal().fg, 0.6))
        Row({ space: 8 }) {
          Text(Format.bytes(this.usage !== undefined ? this.usage.todayBytes : 0).value)
            .fontSize(84)
            .fontWeight(FontWeight.Lighter)
            .maxLines(1)
            .fontColor(this.pal().fg)
          Text(Format.bytes(this.usage !== undefined ? this.usage.todayBytes : 0).unit)
            .fontSize(18)
            .fontColor(TodayArt.withAlpha(this.pal().fg, 0.6))
            .margin({ bottom: 14 })
        }
        .alignItems(VerticalAlign.Bottom)
        Row({ space: 36 }) {
          this.stat(String(TodayArt.stats(this.usage).regions),
            $r('app.plural.today_regions', TodayArt.stats(this.usage).regions), this.pal().fg)
          this.stat(String(TodayArt.stats(this.usage).hours),
            $r('app.plural.today_hours_online', TodayArt.stats(this.usage).hours), this.pal().fg)
          this.stat(TodayArt.stats(this.usage).fastest, $r('app.string.today_fastest'), this.pal().fg)
        }
        Divider()
          .strokeWidth(1)
          .color(TodayArt.withAlpha(this.pal().fg, 0.14))
          .margin({ top: 18, bottom: 14 })
        Row() {
          Text($r('app.string.EntryAbility_label'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().fg)
          Blank()
          Text($r('app.string.term_today'))
            .fontSize(12)
            .fontColor(TodayArt.withAlpha(this.pal().fg, 0.5))
        }
        .width('100%')
      }
      .width('100%')
      .padding(24)
      .alignItems(HorizontalAlign.Start)
    }
    .id(CARD_ID)
    .width('100%')
    .aspectRatio(TODAY_ASPECT)
    .borderRadius(24)
    .clip(true)
    .backgroundColor(this.pal().bg)
    .border({ width: 1, color: '#1AFFFFFF', radius: 24 })
  }

  private styleLabel(s: TodayStyle): Resource {
    switch (s) {
      case TodayStyle.DAWN:
        return $r('app.string.today_style_dawn');
      case TodayStyle.MIST:
        return $r('app.string.today_style_mist');
      default:
        return $r('app.string.today_style_night');
    }
  }

  @Builder
  styles() {
    Row({ space: 12 }) {
      ForEach(TODAY_STYLES, (s: TodayStyle) => {
        Row({ space: 10 }) {
          Circle({ width: 28, height: 28 })
            .fill(TodayArt.palette(s).bg)
            .stroke('#29FFFFFF')
            .strokeWidth(1)
          Text(this.styleLabel(s))
            .fontSize(15)
            .fontColor(Color.White)
        }
        .padding({ start: LengthMetrics.vp(6), end: LengthMetrics.vp(16), top: LengthMetrics.vp(6), bottom: LengthMetrics.vp(6) })
        .borderRadius(20)
        .border({ width: 1, color: s === this.style ? '#99FFFFFF' : '#29FFFFFF', radius: 20 })
        .accessibilityGroup(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilitySelected(s === this.style)
        .onClick(() => {
          if (s !== this.style) {
            Haptics.play(HapticKind.SELECTION);
            this.style = s;
            this.draw();
          }
        })
      }, (s: TodayStyle) => s)
    }
    .margin({ top: 20 })
  }

  @Builder
  actions() {
    Row({ space: 12 }) {
      Button($r('app.string.common_share'))
        .layoutWeight(1)
        .height(48)
        .fontColor(Color.Black)
        .backgroundColor(Color.White)
        .onClick(() => {
          this.share().catch((e: Object) => {
            hilog.warn(0x5A50, 'Today', 'share failed %{public}s', String(e));
          });
        })
      Column() {
        SaveButton({ text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
          .width('100%')
          .height(48)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            if (result !== SaveButtonOnClickResult.SUCCESS) {
              this.flash($r('app.string.today_save_failed'));
              return;
            }
            this.save().then(() => {
              Haptics.play(HapticKind.SUCCESS);
              this.flash($r('app.string.today_saved'));
            }).catch((e: Object) => {
              hilog.warn(0x5A50, 'Today', 'save failed %{public}s', String(e));
              this.flash($r('app.string.today_save_failed'));
            });
          })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 22, right: 22 })
    .margin({ top: 20 })
  }
}
