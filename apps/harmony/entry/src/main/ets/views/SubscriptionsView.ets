/*
 * 订阅段（对照 Android ui/subs SubscriptionsScreen / ImportSheet / SubscriptionImporter，简化）：
 * - 外链导入确认卡（ImportInbox，§16.e⑦ 从不自动导入）：条目、http 警告、信任提示、取消 / 添加；解析失败只显示原因。
 * - 添加订阅：粘贴链接输入框 + PasteButton（安全控件，点按即授予一次读剪贴板）+ 添加（engine.importSubscription）。
 * - 页眉：订阅数（大号）+ “个 · 每 N 小时更新”。
 * - M1-11（U19–U21，同 Android SubscriptionsScreen / SubscriptionReview / SwipeActions / SubscriptionWarning，iOS 同名）：
 *   “更新前显示更改”开着时，更新 / 全部更新先 previewUpdate，出差异确认卡（+ 节点 / − 节点 / 规则变更 + 说明，取消 / 更新）；
 *   最近一次更新的差异卡（覆写已保留 · 场景池已重新检测）；
 *   “流量 · 本月”卡：有流量信息的订阅逐行（名称、“N 个节点 · 到期”、用量条、剩余），§16.e④ 琥珀（≤7 日历日或用量 ≥80%）；
 *   行左滑出“更新 / 删除”，删除第一下变“确认删除”并保持展开、第二下才删（再走 §16.e⑥ 撤销吐司），长按菜单同两项（无障碍）；
 *   其余订阅并入“其他 N 个 ›”，打开“全部订阅”sheet；
 *   “更新”分组：自动更新 6/12/24/48 小时（菜单）、仅在 Wi‑Fi 下更新、更新前显示更改、更新全部。
 * M1-12：扫码 / 从电脑上的 Zephyr 导入（ScanKit）与从文件导入（DocumentViewPicker），见 ImportPickers。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppServices } from '../app/AppServices';
import { ImportInbox } from '../app/ImportInbox';
import { ImportOutcome, SubscriptionImport } from '../app/SubscriptionImport';
import { ImportPickers, PickError, PickResult } from '../app/ImportPickers';
import { ZNavRow } from '../components/ZNavRow';
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
import { ReviewKind, SubscriptionGroups, SubscriptionsModel, SubscriptionWarning, UpdateReview } from '../app/SubscriptionsModel';
import { copySettings, Settings } from '../engine/Model';
import { SettingsCodec } from '../engine/SettingsCodec';
import { ZSection } from '../components/ZSection';
import { ZToggleRow } from '../components/ZToggleRow';

/** 界面测试用组件 id。 */
export const SUBS_REVIEW_CONFIRM_ID: string = 'zephyr.subs.review.confirm';
export const SUBS_REVIEW_ID: string = 'zephyr.subs.review';
export const SUBS_SHOW_CHANGES_ID: string = 'zephyr.subs.showChanges';
export const SUBS_SCAN_QR_ID: string = 'zephyr.subs.scanQr';
export const SUBS_IMPORT_FILE_ID: string = 'zephyr.subs.importFile';
export const SUBS_UPDATE_ALL_ID: string = 'zephyr.subs.updateAll';

export function subsRowId(id: string): string {
  return 'zephyr.subs.row.' + id;
}

export function subsSwipeUpdateId(id: string): string {
  return 'zephyr.subs.swipe.update.' + id;
}

export function subsSwipeDeleteId(id: string): string {
  return 'zephyr.subs.swipe.delete.' + id;
}

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
  @Local autoUpdateHours: number = 12;
  @Local updateOnWifiOnly: boolean = true;
  @Local showChanges: boolean = false;
  @Local review: UpdateReview | undefined = undefined;
  /** 左滑删除已“上膛”（显示“确认删除”）的订阅。 */
  @Local armedDelete: string = '';
  @Local showAll: boolean = false;
  @Local error: string = '';

  private listScroller: ListScroller = new ListScroller();
  private errorTimer: number = -1;
  private minuteTimer: number = -1;

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
    this.streamSubs.push(engine.settings().subscribe((st: Settings) => this.applySettings(st)));
    this.applySettings(engine.settings().value);
    // 每分钟刷新“2 小时前 / 26 天后到期”（同 Android L-P2-9）。
    this.minuteTimer = setInterval(() => {
      this.now = Date.now();
    }, 60000);
  }

  private applySettings(st: Settings): void {
    this.autoUpdateHours = st.autoUpdateHours;
    this.updateOnWifiOnly = st.updateOnWifiOnly;
    this.showChanges = st.showChangesBeforeUpdate;
  }

  private patch(f: (s: Settings) => void): void {
    const svc = AppServices.get();
    const next = copySettings(svc.engine.settings().value);
    f(next);
    svc.settings.update(next).catch(() => {
      this.toast($r('app.string.settings_save_failed'));
      this.applySettings(svc.engine.settings().value);
    });
  }

  private showError(msg: string): void {
    this.error = msg;
    if (this.errorTimer >= 0) {
      clearTimeout(this.errorTimer);
    }
    this.errorTimer = setTimeout(() => {
      this.errorTimer = -1;
      this.error = '';
    }, 4000);
  }

  aboutToDisappear(): void {
    if (this.errorTimer >= 0) {
      clearTimeout(this.errorTimer);
      this.errorTimer = -1;
    }
    if (this.minuteTimer >= 0) {
      clearInterval(this.minuteTimer);
      this.minuteTimer = -1;
    }
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
        this.addError = Labels.importError(o.error, source === ImportSource.FILE);
      }
    }).finally(() => {
      this.adding = false;
    });
  }

  // ── 扫码 / 文件（M1-12） ─────────────────────────────────────────────────
  private scanQr(): void {
    const ctx = this.getUIContext().getHostContext();
    if (this.adding || ctx === undefined) {
      return;
    }
    this.addError = undefined;
    ImportPickers.scanQr(ctx).then((r: PickResult) => {
      if (r.text !== undefined) {
        this.addFromText(ImportSource.QR, r.text);
      } else if (r.error === PickError.UNAVAILABLE) {
        this.addError = $r('app.string.subs_scan_no_camera');
      }
    });
  }

  private pickFile(): void {
    const ctx = this.getUIContext().getHostContext();
    if (this.adding || ctx === undefined) {
      return;
    }
    this.addError = undefined;
    ImportPickers.pickFile(ctx).then((r: PickResult) => {
      if (r.text !== undefined) {
        this.addFromText(ImportSource.FILE, r.text);
      } else if (r.error === PickError.UNREADABLE) {
        this.addError = $r('app.string.subs_error_read_file');
      }
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
  private busy(): boolean {
    return this.updatingAll || this.updating.length > 0;
  }

  private updateOne(s: Subscription): void {
    if (this.updating.indexOf(s.id) >= 0) {
      return;
    }
    this.updating = this.updating.concat([s.id]);
    AppServices.get().engine.updateSubscription(s.id).catch((e: Object) => {
      this.showError(this.text($r('app.string.subs_error_update'), s.name));
    }).finally(() => {
      this.updating = this.updating.filter((id: string) => id !== s.id);
    });
  }

  /** 左滑“更新”：设置开着时先预览差异，等确认卡上的“更新”。 */
  private requestUpdate(s: Subscription): void {
    if (this.busy()) {
      return;
    }
    if (!this.showChanges) {
      this.updateOne(s);
      return;
    }
    this.updating = this.updating.concat([s.id]);
    AppServices.get().engine.previewUpdate(s.id).then((d: SubscriptionDiff) => {
      this.review = SubscriptionsModel.one(s, d);
    }).catch((e: Object) => {
      this.showError(this.text($r('app.string.subs_error_update'), s.name));
    }).finally(() => {
      this.updating = this.updating.filter((id: string) => id !== s.id);
    });
  }

  private runUpdateAll(): void {
    this.updatingAll = true;
    AppServices.get().engine.updateAll().then((d: SubscriptionDiff[]) => {
      this.toast($r('app.plural.subs_updated_count', d.length, d.length));
    }).catch((e: Object) => {
      this.showError(this.str($r('app.string.subs_error_update_all')));
    }).finally(() => {
      this.updatingAll = false;
    });
  }

  private requestUpdateAll(): void {
    if (this.busy()) {
      return;
    }
    if (!this.showChanges) {
      this.runUpdateAll();
      return;
    }
    this.updatingAll = true;
    SubscriptionsModel.previewAll(AppServices.get().engine).then((r: UpdateReview | undefined) => {
      this.updatingAll = false;
      if (r !== undefined) {
        this.review = r;
      } else {
        this.showError(this.str($r('app.string.subs_error_update_all')));
      }
    });
  }

  private confirmReview(): void {
    const r = this.review;
    this.review = undefined;
    if (r === undefined) {
      return;
    }
    if (r.kind === ReviewKind.ONE && r.sub !== undefined) {
      this.updateOne(r.sub);
    } else {
      this.runUpdateAll();
    }
  }

  private str(r: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id) : '';
    } catch (e) {
      return '';
    }
  }

  private plural(r: Resource, n: number, arg: string): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getIntPluralStringValueSync(r.id, n, arg) : '';
    } catch (e) {
      return '';
    }
  }

  /** “N 个节点 · 26 天后到期”。 */
  private nodesLine(s: Subscription): string {
    let t = this.plural($r('app.plural.common_node_count'), s.nodeCount, Format.grouped(s.nodeCount));
    if (s.expiresAt !== undefined) {
      const ex = Format.expiry(s.expiresAt, this.now);
      t += ' · ' + this.expiryText(Labels.expiry(ex), ex.days);
    }
    return t;
  }

  private expiryText(r: Resource, days: number): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx !== undefined ? ctx.resourceManager.getStringSync(r.id, days) : '';
    } catch (e) {
      return '';
    }
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
            .fontColor($r('app.color.screen_red_text'))
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
              .fontColor($r('app.color.screen_amber_text'))
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
            .fontColor($r('app.color.screen_red_text'))
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

        Column() {
          ZNavRow({ title: $r('app.string.subs_scan_qr'), onTap: () => this.scanQr() })
            .id(SUBS_SCAN_QR_ID)
          ZNavRow({ title: $r('app.string.subs_import_desktop'), onTap: () => this.scanQr() })
          ZNavRow({ title: ZTerm.importFromFile, divider: false, onTap: () => this.pickFile() })
            .id(SUBS_IMPORT_FILE_ID)
        }
        .width('100%')
        .enabled(!this.adding)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  delta(v: string, label: ResourceStr, color: ResourceColor) {
    Column({ space: 2 }) {
      Text(v)
        .fontSize(22)
        .fontWeight(FontWeight.Lighter)
        .fontFamily('monospace')
        .fontColor(color)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.screen_t3'))
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deltas(d: SubscriptionDiff) {
    Row({ space: 28 }) {
      this.delta('+' + Format.grouped(d.addedNodes), ZTerm.nodes, $r('app.color.screen_green'))
      this.delta('−' + Format.grouped(d.removedNodes), ZTerm.nodes, $r('app.color.screen_red'))
      this.delta(Format.grouped(d.ruleChanges), $r('app.string.subs_rule_changes'), $r('app.color.screen_t1'))
    }
  }

  private reviewTitle(r: UpdateReview): ResourceStr {
    if (r.kind === ReviewKind.ONE && r.sub !== undefined) {
      return $r('app.string.subs_review_one', r.sub.name);
    }
    return $r('app.plural.subs_review_all', r.count, Format.grouped(r.count));
  }

  /** 更新前差异确认卡（U19，同 Android SubscriptionReviewCard）。 */
  @Builder
  reviewCard(r: UpdateReview) {
    Column() {
      ZCard({ pad: 18 }) {
        Column({ space: 12 }) {
          Text(this.reviewTitle(r))
            .fontSize(17)
            .fontColor($r('app.color.screen_t1'))
            .accessibilityLevel('yes')
          this.deltas(r.diff)
          Text($r('app.string.subs_review_note'))
            .fontSize(13)
            .fontColor($r('app.color.screen_t3'))
          Row({ space: 8 }) {
            Blank()
            Button($r('app.string.common_cancel'))
              .height(34)
              .fontSize(14)
              .fontColor($r('app.color.screen_t1'))
              .backgroundColor($r('app.color.screen_s3'))
              .onClick(() => {
                this.review = undefined;
              })
            Button(ZTerm.update)
              .id(SUBS_REVIEW_CONFIRM_ID)
              .height(34)
              .fontSize(14)
              .fontColor($r('app.color.screen_on_primary'))
              .backgroundColor($r('app.color.screen_primary'))
              .onClick(() => this.confirmReview())
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .id(SUBS_REVIEW_ID)
  }

  /** 最近一次更新的差异卡。 */
  @Builder
  lastDiffCard(s: Subscription) {
    ZCard({ pad: 18 }) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.updatingAll ? $r('app.string.subs_diff_updating', s.name) : $r('app.string.subs_diff_updated', s.name))
            .fontSize(17)
            .fontColor($r('app.color.screen_t1'))
            .layoutWeight(1)
          if (s.updatedAt !== undefined) {
            Text(Labels.ago(Format.ago(s.updatedAt, this.now)))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
        }
        .width('100%')
        if (s.lastDiff !== undefined) {
          this.deltas(s.lastDiff)
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl'))
          Row({ space: 10 }) {
            Circle().width(7).height(7).fill($r('app.color.screen_green'))
            Text(this.diffNote(s.lastDiff))
              .fontSize(14)
              .fontColor($r('app.color.screen_t2'))
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private diffNote(d: SubscriptionDiff): string {
    const parts: string[] = [];
    if (d.overridesKept) {
      parts.push(this.str($r('app.string.subs_overrides_kept')));
    }
    if (d.scenesRetested) {
      parts.push(this.str($r('app.string.subs_scenes_retested')));
    }
    return parts.join(' · ');
  }

  /** 左滑操作（同 Android SwipeActionsRow：更新 / 删除，删除两步）。 */
  @Builder
  swipeActions(s: Subscription) {
    Row() {
      Text(this.isUpdating(s) ? $r('app.string.subs_swipe_updating') : ZTerm.update)
        .id(subsSwipeUpdateId(s.id))
        .fontSize(14)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(84)
        .height('100%')
        .backgroundColor(this.theme.accentColor())
        .onClick(() => {
          this.listScroller.closeAllSwipeActions();
          this.requestUpdate(s);
        })
      Text(this.armedDelete === s.id ? $r('app.string.subs_swipe_confirm_delete') : ZTerm.delete)
        .id(subsSwipeDeleteId(s.id))
        .fontSize(14)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(this.armedDelete === s.id ? 104 : 84)
        .height('100%')
        .backgroundColor($r('app.color.screen_red'))
        .onClick(() => {
          if (this.armedDelete !== s.id) {
            // 第一下：上膛，保持展开（审计 U15）。
            this.armedDelete = s.id;
            return;
          }
          this.armedDelete = '';
          this.listScroller.closeAllSwipeActions();
          this.delete(s);
        })
    }
    .height('100%')
  }

  @Builder
  rowMenu(s: Subscription) {
    Menu() {
      MenuItem({ content: ZTerm.update })
        .onClick(() => this.requestUpdate(s))
      MenuItem({ content: ZTerm.delete })
        .onClick(() => this.confirmDelete(s))
    }
  }

  @Builder
  meteredRow(s: Subscription) {
    Row({ space: 24 }) {
      Column({ space: 4 }) {
        Text(s.name)
          .fontSize(17)
          .fontColor($r('app.color.screen_t1'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.nodesLine(s))
          .fontSize(13)
          .fontColor(SubscriptionWarning.isWarning(s, this.now) ? $r('app.color.screen_amber') : $r('app.color.screen_t3'))
        Progress({ value: SubscriptionsModel.usedFraction(s) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .margin({ top: 6 })
          .color(SubscriptionWarning.isWarning(s, this.now) ? $r('app.color.screen_amber') : $r('app.color.screen_t3'))
          .backgroundColor($r('app.color.screen_s3'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Column({ space: 2 }) {
        Text(s.remainingBytes !== undefined ? Format.bytesText(s.remainingBytes) : '—')
          .fontSize(15)
          .fontFamily('monospace')
          .fontColor($r('app.color.screen_t1'))
        Text($r('app.string.subs_remaining'))
          .fontSize(12)
          .fontColor($r('app.color.screen_t3'))
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.screen_s1'))
  }

  @Builder
  dataCard(g: SubscriptionGroups) {
    Column() {
      List({ scroller: this.listScroller }) {
        ForEach(g.metered, (s: Subscription, i: number) => {
          ListItem() {
            Column() {
              if (i > 0) {
                Divider().strokeWidth(0.5).color($r('app.color.screen_hl'))
              }
              this.meteredRow(s)
            }
          }
          .id(subsRowId(s.id))
          .swipeAction({
            end: {
              builder: () => {
                this.swipeActions(s)
              },
              onStateChange: (st: SwipeActionState) => {
                if (st === SwipeActionState.COLLAPSED && this.armedDelete === s.id) {
                  this.armedDelete = '';
                }
              }
            },
            edgeEffect: SwipeEdgeEffect.None
          })
          .bindContextMenu(this.rowMenu(s), ResponseType.LongPress)
        }, (s: Subscription) => s.id + ':' + String(s.updatedAt) + ':' + String(s.nodeCount) + ':' + String(s.usedBytes) + ':' +
          String(this.isUpdating(s)) + ':' + String(this.armedDelete === s.id) + ':' + String(this.now))
      }
      .width('100%')
      .enableScrollInteraction(false)
      .edgeEffect(EdgeEffect.None)

      if (g.others > 0) {
        if (g.metered.length > 0) {
          Divider().strokeWidth(0.5).color($r('app.color.screen_hl'))
        }
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text($r('app.plural.subs_others', g.others, g.others))
              .fontSize(16)
              .fontColor($r('app.color.screen_t1'))
            Text($r('app.plural.common_node_count', g.otherNodes, Format.grouped(g.otherNodes)))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('›')
            .fontSize(20)
            .fontColor($r('app.color.screen_t3'))
        }
        .width('100%')
        .padding(18)
        .onClick(() => {
          this.showAll = true;
        })
      }
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor($r('app.color.screen_s1'))
  }

  @Builder
  autoUpdateMenu() {
    Menu() {
      ForEach(SettingsCodec.AUTO_UPDATE_OPTIONS, (h: number) => {
        MenuItem({ content: this.plural($r('app.plural.subs_every_hours'), h, String(h)) })
          .selected(h === this.autoUpdateHours)
          .onClick(() => {
            this.autoUpdateHours = h;
            this.patch((st: Settings) => {
              st.autoUpdateHours = h;
            });
          })
      }, (h: number) => String(h))
    }
  }

  @Builder
  updateSection() {
    ZSection({ header: $r('app.string.subs_section_update') }) {
      Column() {
        Row({ space: 8 }) {
          Text(ZTerm.autoUpdate)
            .fontSize(16)
            .fontColor($r('app.color.screen_t1'))
            .layoutWeight(1)
          Text($r('app.plural.subs_every_hours', this.autoUpdateHours, this.autoUpdateHours))
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
          Text('›')
            .fontSize(18)
            .fontColor($r('app.color.screen_t3'))
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .bindMenu(this.autoUpdateMenu())
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
      }
      ZToggleRow({
        title: $r('app.string.subs_update_wifi_only'),
        isOn: this.updateOnWifiOnly,
        onChange: (on: boolean) => {
          this.updateOnWifiOnly = on;
          this.patch((st: Settings) => {
            st.updateOnWifiOnly = on;
          });
        }
      })
      Column() {
        ZToggleRow({
          title: $r('app.string.subs_show_changes'),
          isOn: this.showChanges,
          onChange: (on: boolean) => {
            this.showChanges = on;
            this.patch((st: Settings) => {
              st.showChangesBeforeUpdate = on;
            });
          }
        })
      }
      .id(SUBS_SHOW_CHANGES_ID)
      Row({ space: 8 }) {
        Text($r('app.string.subs_update_all'))
          .fontSize(16)
          .fontColor(this.busy() ? $r('app.color.screen_t3') : this.theme.accentColor())
          .layoutWeight(1)
        if (this.updatingAll) {
          Text($r('app.string.common_updating'))
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
        }
      }
      .id(SUBS_UPDATE_ALL_ID)
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .onClick(() => this.requestUpdateAll())
    }
  }

  @Builder
  allSheet() {
    Column({ space: 8 }) {
      Text($r('app.string.subs_all_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.screen_t1'))
        .padding({ left: 22, right: 22 })
      Column() {
        ForEach(this.visibleSubs(), (s: Subscription, i: number) => {
          if (i > 0) {
            Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
          }
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(s.name)
                .fontSize(16)
                .fontColor($r('app.color.screen_t1'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.nodesLine(s))
                .fontSize(13)
                .fontColor($r('app.color.screen_t3'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            if (s.remainingBytes !== undefined) {
              Text(Format.bytesText(s.remainingBytes))
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor($r('app.color.screen_t3'))
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }, (s: Subscription) => s.id)
      }
      .borderRadius(16)
      .backgroundColor($r('app.color.screen_s1'))
      .margin({ left: 16, right: 16 })
      Text(this.allFooter())
        .fontSize(13)
        .fontColor($r('app.color.screen_t3'))
        .padding({ left: 22, right: 22, top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, bottom: 24 })
  }

  private allFooter(): string {
    const list = this.visibleSubs();
    let nodes = 0;
    for (const s of list) {
      nodes += s.nodeCount;
    }
    return Format.grouped(list.length) + ' ' + this.plural($r('app.plural.subs_total_unit'), list.length, '') + ' · ' +
      this.plural($r('app.plural.common_node_count'), nodes, Format.grouped(nodes));
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.request !== undefined) {
          this.requestCard(this.request)
        }

        Row({ space: 8 }) {
          Text(Format.grouped(this.summary !== undefined ? this.summary.count : this.visibleSubs().length))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor($r('app.color.screen_t1'))
          Text(this.plural($r('app.plural.subs_total_unit'), this.summary !== undefined ? this.summary.count : 0, '') + ' · ' +
            this.plural($r('app.plural.subs_update_every'), this.autoUpdateHours, String(this.autoUpdateHours)))
            .fontSize(15)
            .fontColor($r('app.color.screen_t3'))
            .margin({ bottom: 8 })
            .layoutWeight(1)
          Button($r('app.string.subs_add'))
            .height(32)
            .fontSize(14)
            .fontColor($r('app.color.screen_on_primary'))
            .backgroundColor($r('app.color.screen_primary'))
            .margin({ bottom: 8 })
            .onClick(() => {
              this.showAdd = !this.showAdd;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .padding({ left: 6 })

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
          if (this.review !== undefined) {
            this.reviewCard(this.review)
          } else if (SubscriptionsModel.lastDiff(this.visibleSubs()) !== undefined) {
            this.lastDiffCard(SubscriptionsModel.lastDiff(this.visibleSubs())!)
          }

          Row() {
            Text($r('app.string.subs_section_data'))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
            Blank()
            Text($r('app.string.subs_this_month'))
              .fontSize(13)
              .fontColor($r('app.color.screen_t3'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6 })
          this.dataCard(SubscriptionsModel.groups(this.visibleSubs(), this.summary))

          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(13)
              .fontColor($r('app.color.screen_red_text'))
              .padding({ left: 6, right: 6 })
          }

          this.updateSection()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 48 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .bindSheet(this.showAll, this.allSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: true,
      dragBar: true,
      backgroundColor: $r('app.color.screen_bg'),
      onDisappear: () => {
        this.showAll = false;
      }
    })
  }
}
