/*
 * UI 进程把引擎状态写成服务卡片快照并推给已添加的卡片（契约 §17.c；对照 Android ZephyrWidget.refreshAll）：
 * - 连接状态变化（含模式 / 全局节点）与场景变化：立即写；
 * - 连接期间：UI 进程在前台时每 CARD_LIVE_REFRESH_MS（60 s）重写快照（今日用量、场景出口），只写文件不推卡片；
 *   每 60 s 的 updateForm 由 VPN 扩展进程读文件发起（#297：UI 进程进后台会被冻结）；
 * - 文案按当前语言格式化好再写（卡片进程不加载引擎）。
 * 详情行同 Android：连接中 → “连接中…”；未连接 → “未连接”；已连接 → “模式 · 出口”（规则 = 第一个场景的出口，全局 = 全局节点，直连无出口）。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Format } from '../common/Format';
import { Labels } from '../common/Labels';
import { ConnectionState, ConnectionStatus, ProxyMode, Scene } from '../engine/Model';
import { Subscription } from '../engine/Stream';
import { ZephyrEngine } from '../engine/ZephyrEngine';
import { ZTerm } from '../generated/ZTerms';
import { CARD_LIVE_REFRESH_MS, CARD_SCENE_ROWS, CardScene, CardSnapshot, CardSnapshots } from './CardSnapshot';
import { CardPush } from './CardPush';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x5A50;
const TAG: string = 'CardSync';

export class CardSync {
  private readonly ctx: common.UIAbilityContext;
  private readonly engine: ZephyrEngine;
  private subs: Subscription[] = [];
  private timer: number = -1;
  private lastKey: string = '';
  private scenes: Scene[] = [];
  private pending: boolean = false;

  constructor(ctx: common.UIAbilityContext, engine: ZephyrEngine) {
    this.ctx = ctx;
    this.engine = engine;
  }

  start(): void {
    this.subs.push(this.engine.connectionState().subscribe((c: ConnectionState) => {
      const key = c.status + '|' + c.mode + '|' + String(c.globalNodeId ?? '');
      if (key !== this.lastKey) {
        this.lastKey = key;
        this.schedule(c.status === ConnectionStatus.CONNECTED);
        this.refresh();
      }
    }));
    this.subs.push(this.engine.scenes().subscribe((s: Scene[]) => {
      this.scenes = s;
      this.refresh();
    }));
  }

  dispose(): void {
    this.subs.forEach((s: Subscription) => s.cancel());
    this.subs = [];
    this.schedule(false);
  }

  private schedule(live: boolean): void {
    if (live && this.timer < 0) {
      this.timer = setInterval(() => this.refresh(false), CARD_LIVE_REFRESH_MS);
    } else if (!live && this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private str(r: Resource | string, ...args: (string | number)[]): string {
    if (typeof r === 'string') {
      return r;
    }
    try {
      return this.ctx.resourceManager.getStringSync(r.id, ...args);
    } catch (e) {
      return '';
    }
  }

  /** 同时只跑一次；跑的期间又来的请求合并成结束后再跑一次。 */
  private refresh(push: boolean = true): void {
    if (this.pending) {
      return;
    }
    this.pending = true;
    this.build().then((s: CardSnapshot) => this.publish(s, push)).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'snapshot failed: %{public}s', String(e));
    }).finally(() => {
      this.pending = false;
    });
  }

  private async build(): Promise<CardSnapshot> {
    const c = this.engine.connectionState().value;
    const on = c.status === ConnectionStatus.CONNECTED;
    const s = new CardSnapshot();
    s.on = on;
    s.busy = c.status === ConnectionStatus.CONNECTING || c.status === ConnectionStatus.DISCONNECTING;
    s.title = on ? this.str($r('app.string.common_status_connected')) : 'Zephyr';
    if (c.status === ConnectionStatus.CONNECTING) {
      s.detail = this.str($r('app.string.common_status_connecting_ellipsis'));
    } else if (c.status === ConnectionStatus.FAILED) {
      s.detail = this.str(ZTerm.statusFailed);
    } else if (!on) {
      s.detail = this.str(ZTerm.statusDisconnected);
    } else {
      const exit = await this.exitName(c);
      s.detail = this.str(Labels.mode(c.mode)) + (exit.length > 0 ? ' · ' + exit : '');
    }
    let today = 0;
    try {
      today = (await this.engine.usageToday()).todayBytes;
    } catch (e) {
      today = 0;
    }
    const tv = Format.bytes(today);
    const zero = Format.bytes(0);
    s.today = this.str($r('app.string.widget_today'), tv.value, tv.unit);
    s.todayZero = this.str($r('app.string.widget_today'), zero.value, zero.unit);
    s.day = CardSnapshots.dayKey(Date.now());
    s.scenesTitle = this.str(ZTerm.scenes);
    s.toggleLabel = this.str(on ? ZTerm.disconnect : $r('app.string.common_connect'));
    s.scenes = this.scenes.slice(0, CARD_SCENE_ROWS).map((sc: Scene) => {
      const r = new CardScene();
      const n = Labels.sceneName(sc);
      r.name = typeof n === 'string' ? n : this.str(n as Resource);
      r.exit = sc.selected.region + '  ' + sc.selected.name;
      r.ms = sc.selected.latencyMs !== undefined && sc.selected.latencyMs >= 0 ? sc.selected.latencyMs + ' ms' : '';
      return r;
    });
    return s;
  }

  private async exitName(c: ConnectionState): Promise<string> {
    if (c.mode === ProxyMode.GLOBAL && c.globalNodeId !== undefined) {
      try {
        return (await this.engine.node(c.globalNodeId)).summary.name;
      } catch (e) {
        return '';
      }
    }
    if (c.mode === ProxyMode.RULE && this.scenes.length > 0) {
      return this.scenes[0].selected.name;
    }
    return '';
  }

  private publish(s: CardSnapshot, push: boolean): void {
    const dir = this.ctx.filesDir;
    try {
      CardStore.saveSnapshot(dir, s);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save snapshot failed: %{public}s', String(e));
    }
    if (push) {
      CardPush.push(dir, s);
    }
  }
}
