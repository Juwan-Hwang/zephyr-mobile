/*
 * 设置 › 诊断 › 日志（对照 Android LogsScreen）：级别分段（§16.h：debug 抬高内核级别，离开回 info，由 LogsModel 处理）、
 * 暂停 / 继续、清空；新行到达时滚到底部（暂停时不滚）。最多 500 行（LogsModel.LOG_CAPACITY）。
 */
import { AppServices } from '../app/AppServices';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZEmpty } from '../components/ZEmpty';
import { ZSegmented } from '../components/ZSegmented';
import { LogLevel, LogLine } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';

const LEVELS: LogLevel[] = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR];

@ComponentV2
export struct LogsPage {
  @Local lines: LogLine[] = [];
  @Local level: LogLevel = LogLevel.INFO;
  @Local paused: boolean = false;
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

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        ZSegmented({
          options: [Labels.logLevel(LogLevel.DEBUG), Labels.logLevel(LogLevel.INFO), Labels.logLevel(LogLevel.WARNING),
            Labels.logLevel(LogLevel.ERROR)],
          selected: LEVELS.indexOf(this.level),
          onSelect: (i: number) => AppServices.get().logs.setLevel(LEVELS[i])
        })

        Row({ space: 8 }) {
          Button(this.paused ? $r('app.string.logs_resume') : $r('app.string.logs_pause'))
            .height(30)
            .fontSize(13)
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => AppServices.get().logs.togglePause())
          Button($r('app.string.logs_clear'))
            .height(30)
            .fontSize(13)
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => AppServices.get().logs.clear())
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
    .title($r('app.string.logs_title'))
    .backgroundColor($r('app.color.screen_bg'))
  }
}
