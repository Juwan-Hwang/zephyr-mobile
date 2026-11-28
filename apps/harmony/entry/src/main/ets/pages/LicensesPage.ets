/*
 * 设置 › 关于 › 开源许可（M1-17；对照 Android LicensesScreen）：许可声明 + 源码位置（mobile-v<版本> tag），
 * 然后是 NOTICES 与全部许可原文，等宽字体、始终从左到右（RTL 语言也一样）。文件从 rawfile 异步读，懒渲染。
 */
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { LICENSE_DOCS, LicenseDoc, LicenseRow, LicenseRowSource, Licenses, SOURCE_URL } from '../app/Licenses';

@ComponentV2
export struct LicensesPage {
  @Local loaded: boolean = false;
  @Local empty: boolean = false;
  @Local version: string = '';
  private source: LicenseRowSource = new LicenseRowSource();

  aboutToAppear(): void {
    try {
      this.version = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (e) {
      this.version = '';
    }
    this.load().catch(() => {
      this.empty = true;
      this.loaded = true;
    });
  }

  private async load(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    const texts = new Map<LicenseDoc, string>();
    if (ctx !== undefined) {
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      for (const doc of LICENSE_DOCS) {
        try {
          const bytes = await ctx.resourceManager.getRawFileContent(Licenses.rawPath(doc));
          texts.set(doc, decoder.decodeToString(bytes));
        } catch (e) {
          // 缺这一份：跳过
        }
      }
    }
    const rows = Licenses.rows(texts);
    this.source.set(rows);
    this.empty = rows.length === 0;
    this.loaded = true;
  }

  private title(doc: LicenseDoc): Resource {
    switch (doc) {
      case LicenseDoc.NOTICES:
        return $r('app.string.licenses_section_notices');
      case LicenseDoc.TEXTS:
        return $r('app.string.licenses_section_texts');
      default:
        return $r('app.string.licenses_section_app');
    }
  }

  build() {
    NavDestination() {
      List() {
        ListItem() {
          Text($r('app.string.licenses_intro', SOURCE_URL, Licenses.sourceTag(this.version)))
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
            .padding({ left: 22, right: 22, top: 8, bottom: 8 })
        }
        if (this.loaded && this.empty) {
          ListItem() {
            Text($r('app.string.licenses_unavailable'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .fontSize(16)
              .fontColor($r('app.color.screen_t3'))
              .padding(24)
          }
        }
        LazyForEach(this.source, (row: LicenseRow) => {
          ListItem() {
            if (row.header) {
              Text(this.title(row.doc))
                .fontSize(13)
                .fontColor($r('app.color.screen_t3'))
                .padding({ left: 22, right: 22, top: 20, bottom: 6 })
            } else {
              Text(row.text)
                .width('100%')
                .fontSize(11)
                .fontFamily('monospace')
                .fontColor($r('app.color.screen_t1'))
                .textAlign(TextAlign.Start)
                .direction(Direction.Ltr)
                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            }
          }
        }, (row: LicenseRow) => row.key)
      }
      .width('100%')
      .height('100%')
      .cachedCount(8)
      .scrollBar(BarState.Auto)
    }
    .title($r('app.string.settings_licenses'))
    .backgroundColor($r('app.color.screen_bg'))
  }
}
