/*
 * 订阅段（对照 Android ui/subs SubscriptionsScreen / ImportSheet / SubscriptionImporter，简化）：
 * - 外链导入确认卡（ImportInbox，§16.e⑦ 从不自动导入）：条目、http 警告、信任提示、取消 / 添加；解析失败只显示原因。
 * - 添加订阅：粘贴链接输入框 + PasteButton（安全控件，点按即授予一次读剪贴板）+ 添加（engine.importSubscription）。
 * - 列表：名称、节点数、更新时间、流量条（已用 / 总量）、到期；更新（engine.updateSubscription）/ 删除（二次确认）；全部更新。
 * 暂未移植：扫码、文件导入、从桌面端导入、更新前预览差异、左滑操作。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppServices } from '../app/AppServices';
import { ImportInbox } from '../app/ImportInbox';
import { ImportOutcome, SubscriptionImport } from '../app/SubscriptionImport';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ZCard } from '../components/ZCard';
import { ZEmpty } from '../components/ZEmpty';
import { ImportRequest } from '../entryability/DeepLink';
import { ImportItem, ImportSource, Subscription, SubscriptionDiff, SubscriptionsSummary } from '../engine/Model';
import { Subscription as StreamSub } from '../engine/Stream';
import { ZTerm } from '../generated/ZTerms';
import { ZTheme } from '../common/Theme';
import { HapticKind, Haptics } from '../app/Haptics';
import { UndoableDelete } from '../app/UndoableDelete';
import { hilog } from '@kit.PerformanceAnalysisKit';

@ComponentV2
export struct SubscriptionsView {
  @Local subs: Subscription[] = [];
  @Local summary: SubscriptionsSummary | undefined = undefined;
  @Local request: ImportRequest | undefined = undefined;
  @Local adding: boolean = false;
  @Local showAdd: boolean = false;
  @Local link: string = '';
  @Local addError: Resource | undefined = undefined;
  @Local updating: string[] = [];
  @Local updatingAll: boolean = false;
  @Local now: number = Date.now();
  @Local theme: ZTheme = ZTheme.shared();
  /** 已确认删除、还在撤销窗口里的订阅（先从列表隐藏，窗口结束才真正删除）。 */
  @Local pendingDeletes: string[] = [];

  private streamSubs: StreamSub[] = [];

  aboutToAppear(): void {
    const engine = AppServices.get().engine;
    this.streamSubs.push(engine.subscriptions().subscribe((list: Subscription[]) => {
      this.subs = list;
      this.now = Date.now();
      this.refreshSummary();
    }));
    this.streamSubs.push(ImportInbox.stream().subscribe((r: ImportRequest | undefined) => {
      this.request = r;
    }));
  }

  aboutToDisappear(): void {
    for (const s of this.streamSubs) {
      s.cancel();
    }
    this.streamSubs = [];
  }

  private refreshSummary(): void {
    AppServices.get().engine.subscriptionsSummary().then((s: SubscriptionsSummary) => {
      this.summary = s;
    }).catch(() => {});
  }

  private toast(msg: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private reportOutcome(o: ImportOutcome): void {
    if (o.added > 0 && o.first !== undefined) {
      const first = o.first;
      this.toast(o.added === 1
        ? $r('app.plural.subs_added', first.nodeCount, first.name, Format.grouped(first.nodeCount))
        : $r('app.plural.subs_added_many', o.added, o.added));
    }
    if (o.failed > 0 && o.added > 0) {
      this.toast($r('app.plural.subs_import_some_failed', o.failed, o.failed));
    }
  }

  // ── 添加（粘贴 / 链接） ─────────────────────────────────────────────────
  private addFromText(source: ImportSource, text: string): void {
    if (this.adding) {
      return;
    }
    this.adding = true;
    this.addError = undefined;
    SubscriptionImport.importText(AppServices.get().engine, source, text).then((o: ImportOutcome) => {
      if (o.added > 0) {
        this.link = '';
        this.showAdd = false;
        this.reportOutcome(o);
      } else if (o.error !== undefined) {
        this.addError = Labels.importError(o.error);
      }
    }).finally(() => {
      this.adding = false;
    });
  }

  private pasteFromClipboard(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      const text = data.getRecordCount() > 0 ? data.getPrimaryText() : '';
      if (text === undefined || text.trim().length === 0) {
        this.addError = $r('app.string.subs_error_clipboard_empty');
        return;
      }
      this.link = text.trim();
      this.addFromText(ImportSource.CLIPBOARD, text);
    }).catch((e: BusinessError) => {
      this.addError = $r('app.string.subs_error_clipboard_empty');
    });
  }

  // ── 外链确认 ────────────────────────────────────────────────────────────
  private requestItems(): ImportItem[] {
    const r = this.request;
    return r !== undefined && r.payload !== undefined ? r.payload.items : [];
  }

  private anyInsecure(): boolean {
    return this.requestItems().some((it: ImportItem) => SubscriptionImport.isInsecure(it.url));
  }

  private dismissRequest(): void {
    const r = this.request;
    if (r !== undefined) {
      ImportInbox.consume(r.id);
    }
  }

  private confirmRequest(): void {
    const r = this.request;
    if (r === undefined || this.adding) {
      return;
    }
    this.adding = true;
    SubscriptionImport.importItems(AppServices.get().engine, ImportSource.URL, this.requestItems())
      .then((o: ImportOutcome) => {
        ImportInbox.consume(r.id);
        if (o.added === 0 && o.error !== undefined) {
          this.toast(Labels.importError(o.error));
        } else {
          this.reportOutcome(o);
        }
      })
      .finally(() => {
        this.adding = false;
      });
  }

  // ── 更新 / 删除 ─────────────────────────────────────────────────────────
  private update(s: Subscription): void {
    if (this.updating.indexOf(s.id) >= 0) {
      return;
    }
    this.updating = this.updating.concat([s.id]);
    AppServices.get().engine.updateSubscription(s.id).then((d: SubscriptionDiff) => {
      this.toast($r('app.string.subs_diff_updated', s.name));
    }).catch((e: Object) => {
      this.toast($r('app.string.subs_error_update', s.name));
    }).finally(() => {
      this.updating = this.updating.filter((id: string) => id !== s.id);
    });
  }

  private updateAll(): void {
    if (this.updatingAll) {
      return;
    }
    this.updatingAll = true;
    AppServices.get().engine.updateAll().then((d: SubscriptionDiff[]) => {
      this.toast($r('app.plural.subs_updated_count', d.length, d.length));
    }).catch((e: Object) => {
      this.toast($r('app.string.subs_error_update_all'));
    }).finally(() => {
      this.updatingAll = false;
    });
  }

  private confirmDelete(s: Subscription): void {
    this.getUIContext().showAlertDialog({
      message: s.name,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.subs_swipe_confirm_delete'),
        fontColor: $r('app.color.screen_red'),
        action: () => this.delete(s)
      }
    });
  }

  /** 确认后先隐藏，出撤销吐司（§16.e⑥）；窗口结束（或被下一条吐司顶替）才调 deleteSubscription（app/UndoableDelete）。 */
  private delete(s: Subscription): void {
    Haptics.play(HapticKind.WARNING);
    const svc = AppServices.get();
    const id = s.id;
    UndoableDelete.run(svc.toasts, {
      message: this.text($r('app.string.subs_deleted'), s.name),
      hide: () => {
        this.pendingDeletes = this.pendingDeletes.concat([id]);
      },
      unhide: () => {
        this.pendingDeletes = this.pendingDeletes.filter((x: string) => x !== id);
      },
      commit: () => svc.engine.deleteSubscription(id),
      onError: (e: Object) => {
        this.toast($r('app.string.subs_error_delete', s.name));
      },
      log: (m: string) => {
        hilog.info(0x5A50, 'SubscriptionsView', 'delete %{public}s: %{public}s', id, m);
      }
    });
  }

  private text(r: Resource, arg: string): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, arg) : arg;
    } catch (e) {
      return arg;
    }
  }

  private visibleSubs(): Subscription[] {
    return this.subs.filter((s: Subscription) => this.pendingDeletes.indexOf(s.id) < 0);
  }

  private isUpdating(s: Subscription): boolean {
    return this.updatingAll || this.updating.indexOf(s.id) >= 0;
  }

  // ── 视图 ───────────────────────────────────────────────────────────────
  @Builder
  requestCard(r: ImportRequest) {
    ZCard() {
      Column({ space: 8 }) {
        if (r.payload === undefined) {
          Text($r('app.string.subs_error_invalid_link'))
            .fontSize(15)
            .fontColor($r('app.color.screen_red'))
          Button($r('app.string.common_cancel'))
            .fontSize(14)
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => this.dismissRequest())
        } else {
          Text($r('app.plural.subs_import_confirm_title', this.requestItems().length, this.requestItems().length))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.screen_t1'))
          ForEach(this.requestItems(), (it: ImportItem) => {
            Column({ space: 2 }) {
              Text(SubscriptionImport.displayName(it))
                .fontSize(15)
                .fontColor($r('app.color.screen_t1'))
              Text(it.url)
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor($r('app.color.screen_t3'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .ellipsisMode(EllipsisMode.CENTER)
            }
            .alignItems(HorizontalAlign.Start)
          }, (it: ImportItem) => it.url)
          Text($r('app.string.subs_import_source', r.scheme))
            .fontSize(12)
            .fontColor($r('app.color.screen_t3'))
          if (this.anyInsecure()) {
            Text($r('app.string.subs_import_insecure'))
              .fontSize(13)
              .fontColor($r('app.color.screen_amber'))
          }
          Text($r('app.string.subs_import_trust'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
          Row({ space: 8 }) {
            Button($r('app.string.common_cancel'))
              .layoutWeight(1)
              .fontSize(15)
              .fontColor($r('app.color.screen_t1'))
              .backgroundColor($r('app.color.screen_s3'))
              .onClick(() => this.dismissRequest())
            Button(this.adding ? $r('app.string.common_adding') : $r('app.string.common_add'))
              .layoutWeight(1)
              .fontSize(15)
              .enabled(!this.adding)
              .fontColor($r('app.color.screen_on_primary'))
              .backgroundColor($r('app.color.screen_primary'))
              .onClick(() => this.confirmRequest())
          }
          .width('100%')
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  addCard() {
    ZCard() {
      Column({ space: 10 }) {
        TextArea({ text: this.link, placeholder: $r('app.string.subs_paste_placeholder') })
          .height(88)
          .fontSize(14)
          .backgroundColor($r('app.color.screen_s3'))
          .fontColor($r('app.color.screen_t1'))
          .onChange((v: string) => {
            this.link = v;
            this.addError = undefined;
          })
        if (this.addError !== undefined) {
          Text(this.addError)
            .fontSize(13)
            .fontColor($r('app.color.screen_red'))
        }
        Row({ space: 8 }) {
          PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
            .fontSize(14)
            .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
              if (result === PasteButtonOnClickResult.SUCCESS) {
                this.pasteFromClipboard();
              }
            })
          Blank()
          Button($r('app.string.common_cancel'))
            .fontSize(14)
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => {
              this.showAdd = false;
              this.addError = undefined;
            })
          Button(this.adding ? $r('app.string.common_adding') : $r('app.string.common_add'))
            .fontSize(14)
            .enabled(!this.adding && this.link.trim().length > 0)
            .fontColor($r('app.color.screen_on_primary'))
            .backgroundColor($r('app.color.screen_primary'))
            .onClick(() => this.addFromText(ImportSource.URL, this.link))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  subCard(s: Subscription) {
    ZCard() {
      Column({ space: 6 }) {
        Text(s.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.screen_t1'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text($r('app.plural.common_node_count', s.nodeCount, Format.grouped(s.nodeCount)))
            .fontSize(13)
            .fontColor($r('app.color.screen_t2'))
          if (s.updatedAt !== undefined) {
            Text(Labels.ago(Format.ago(s.updatedAt, this.now)))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
          if (s.expiresAt !== undefined) {
            Text(Labels.expiry(Format.expiry(s.expiresAt, this.now)))
              .fontSize(13)
              .fontColor(s.expiresAt <= this.now ? $r('app.color.screen_red') : $r('app.color.screen_t3'))
          }
        }
        if (Format.ratio(s.usedBytes, s.totalBytes) !== undefined) {
          Progress({ value: s.usedBytes ?? 0, total: s.totalBytes ?? 1, type: ProgressType.Linear })
            .width('100%')
            .color(this.theme.accentColor())
            .backgroundColor($r('app.color.screen_s3'))
          Text(Format.bytesText(s.usedBytes ?? 0) + ' / ' + Format.bytesText(s.totalBytes ?? 0))
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor($r('app.color.screen_t3'))
        }
        Row({ space: 8 }) {
          Button(this.isUpdating(s) ? $r('app.string.subs_swipe_updating') : ZTerm.update)
            .height(30)
            .fontSize(13)
            .enabled(!this.isUpdating(s))
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => this.update(s))
          Button(ZTerm.delete)
            .height(30)
            .fontSize(13)
            .fontColor($r('app.color.screen_red'))
            .backgroundColor($r('app.color.screen_s3'))
            .onClick(() => this.confirmDelete(s))
        }
        .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.request !== undefined) {
          this.requestCard(this.request)
        }

        Row({ space: 8 }) {
          if (this.summary !== undefined) {
            Text(Format.grouped(this.summary.count) + ' · ')
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
            Text($r('app.plural.common_node_count', this.summary.totalNodes, Format.grouped(this.summary.totalNodes)))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
          Blank()
          Button($r('app.string.subs_add'))
            .height(32)
            .fontSize(14)
            .fontColor($r('app.color.screen_on_primary'))
            .backgroundColor($r('app.color.screen_primary'))
            .onClick(() => {
              this.showAdd = !this.showAdd;
            })
        }
        .width('100%')

        if (this.showAdd) {
          this.addCard()
        }

        if (this.visibleSubs().length === 0) {
          ZEmpty({
            title: $r('app.string.connect_no_subscription'),
            message: $r('app.string.nodes_empty_message'),
            action: $r('app.string.subs_add'),
            onAction: () => {
              this.showAdd = true;
            }
          })
        } else {
          ForEach(this.visibleSubs(), (s: Subscription) => {
            this.subCard(s)
          }, (s: Subscription) => s.id + ':' + String(s.updatedAt) + ':' + String(s.nodeCount) + ':' + String(this.isUpdating(s)))

          Button(this.updatingAll ? $r('app.string.common_updating') : $r('app.string.subs_update_all'))
            .width('100%')
            .height(44)
            .fontSize(15)
            .enabled(!this.updatingAll)
            .fontColor($r('app.color.screen_t1'))
            .backgroundColor($r('app.color.screen_s1'))
            .onClick(() => this.updateAll())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
