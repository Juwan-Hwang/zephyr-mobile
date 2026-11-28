/*
 * 设置 › 诊断 › 日志（对照 Android LogsScreen）：级别分段（§16.h：debug 抬高内核级别，离开回 info，由 LogsModel 处理）、
 * 暂停 / 继续、清空；新行到达时滚到底部（暂停时不滚）。最多 500 行（LogsModel.LOG_CAPACITY）。
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { ZBtn } from '../common/ZButtonMods';
import { bundleManager, common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { AppServices } from '../app/AppServices';
import { LogsModel } from '../app/LogsModel';
import { Format } from '../common/Format';
import { ZTheme } from '../common/Theme';
import { Labels } from '../common/Labels';
import { ZEmpty } from '../components/ZEmpty';
import { ZSegmented } from '../components/ZSegmented';
import { LogLevel, LogLine } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';

export const LOGS_SHARE_ID: string = 'zephyr.logs.share';

const LEVELS: LogLevel[] = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR];

@ComponentV2
export struct LogsPage {
  @Local lines: LogLine[] = [];
  @Local level: LogLevel = LogLevel.INFO;
  @Local paused: boolean = false;
  @Local theme: ZTheme = ZTheme.shared();
  private scroller: Scroller = new Scroller();
  private subs: StreamSub[] = [];

  aboutToAppear(): void {
    const logs = AppServices.get().logs;
    this.subs.push(logs.lines.subscribe((l: LogLine[]) => {
      this.lines = l;
      if (!this.paused && l.length > 0) {
        try {
          this.scroller.scrollEdge(Edge.Bottom);
        } catch (e) {
          // 列表首帧还没绑定 scroller：忽略，下一行再滚。
        }
      }
    }));
    this.subs.push(logs.level.subscribe((l: LogLevel) => {
      this.level = l;
    }));
    this.subs.push(logs.paused.subscribe((p: boolean) => {
      this.paused = p;
    }));
    logs.start();
  }

  aboutToDisappear(): void {
    for (const s of this.subs) {
      s.cancel();
    }
    this.subs = [];
    AppServices.get().logs.stop();
  }

  /** 分享（同 Android LogsScreen）：开了“共享诊断数据”才在日志前加诊断摘要（§16.c）；走系统分享面板，纯文本。 */
  private async share(): Promise<void> {
    const svc = AppServices.get();
    const s = svc.engine.settings().value;
    let diag: string | undefined = undefined;
    if (s.shareDiagnostics) {
      let app = '';
      try {
        const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        app = info.versionName + ' (' + info.versionCode + ')';
      } catch (e) {
        app = '';
      }
      const os = deviceInfo.displayVersion + ' (API ' + deviceInfo.sdkApiVersion + ')';
      diag = LogsModel.diagnosticsSummary(app, os, s, []);
    }
    const text = svc.logs.exportText(diag);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: text
    };
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const controller = new systemShare.ShareController(new systemShare.SharedData(record));
    await controller.show(ctx, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ZSegmented({
          options: [Labels.logLevel(LogLevel.DEBUG), Labels.logLevel(LogLevel.INFO), Labels.logLevel(LogLevel.WARNING),
            Labels.logLevel(LogLevel.ERROR)],
          selected: LEVELS.indexOf(this.level),
          onSelect: (i: number) => AppServices.get().logs.setLevel(LEVELS[i])
        })

        Row({ space: 4 }) {
          Button(this.paused ? $r('app.string.logs_resume') : $r('app.string.logs_pause'))
            .attributeModifier(ZBtn.toolbar(this.theme.accentColor()))
            .onClick(() => AppServices.get().logs.togglePause())
          Button($r('app.string.logs_clear'))
            .attributeModifier(ZBtn.toolbar(this.theme.accentColor()))
            .enabled(this.lines.length > 0)
            .onClick(() => AppServices.get().logs.clear())
          Button($r('app.string.common_share'))
            .attributeModifier(ZBtn.toolbar(this.theme.accentColor()))
            .id(LOGS_SHARE_ID)
            .enabled(this.lines.length > 0)
            .onClick(() => {
              this.share().catch(() => {});
            })
        }

        if (this.lines.length === 0) {
          ZEmpty({ title: $r('app.string.logs_empty') })
        } else {
          List({ scroller: this.scroller }) {
            ForEach(this.lines, (l: LogLine) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(Format.time(l.at))
                    .fontSize(11)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.screen_t3'))
                  Text(Labels.logLevel(l.level))
                    .fontSize(11)
                    .fontColor(Labels.logLevelColor(l.level))
                    .width(44)
                  Text(l.message)
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.screen_t1'))
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .padding({ top: 4, bottom: 4 })
              }
            }, (l: LogLine, i: number) => String(l.at) + ':' + String(i) + ':' + l.message.length)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .title(ZTerm.logs)
    .backgroundColor($r('app.color.screen_bg'))
  }
}
