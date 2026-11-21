/*
 * 指令计划（契约 §16.d，原型 render() / PLAN / apply()，index.html ~1034；对照 Android CommandPlanner、iOS CommandPlanner）：
 * 把解析结果变成“一条可预览的更改”。出口变化一律先出预览卡（含出口 IP 行），用户点“应用”才执行，执行后出撤销吐司。
 * - 服务 + 地区：只钉该服务的例外（setSceneException）；撤销恢复原例外（原来没有则 undefined）。
 * - 场景词（视频）+ 地区：整个场景 applySceneChange；撤销回到原节点。
 * - “其他”服务 + 直连：overrideHost(host, direct, 持久)；撤销 overrideHost(host, unchanged)。
 * - AI / 视频服务 + 直连、其他服务 + 地区：不出预览卡（§16.d 有意收窄）。
 * - 4K（§15.h）暂未移植：只出解析卡片。
 * 纯逻辑（只依赖 ZephyrEngine），node / ohosTest 可测。
 */
import { CommandAct, CommandParser, ParsedCommand } from '../engine/CommandParser';
import { ExitChange, NodeId, NodeSummary, Scene, SceneException, SceneKind, TraceTarget } from '../engine/Model';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export enum CommandPlanKind {
  EXIT = 'exit',
  NO_NODES = 'no_nodes',
  DIRECT = 'direct'
}

export class CommandPlan {
  kind: CommandPlanKind;
  /** 服务显示名（场景词时为空，由界面用场景名）。 */
  serviceName: string;
  isSceneWord: boolean;
  scene: Scene | undefined;
  appId: string | undefined;
  regionCode: string;
  available: number;
  node: NodeSummary | undefined;
  /** 出口地区不变时为 undefined（原型 same：不显示出口 IP 行）。 */
  change: ExitChange | undefined;
  /** “Claude 将不再使用固定出口 US-Fixed-01”：原例外节点名。 */
  releasesPin: string | undefined;
  previousPin: NodeId | undefined;
  /** 整场景切换前的节点。 */
  previousSelected: NodeId | undefined;
  host: string | undefined;

  constructor(kind: CommandPlanKind) {
    this.kind = kind;
    this.serviceName = '';
    this.isSceneWord = false;
    this.scene = undefined;
    this.appId = undefined;
    this.regionCode = '';
    this.available = 0;
    this.node = undefined;
    this.change = undefined;
    this.releasesPin = undefined;
    this.previousPin = undefined;
    this.previousSelected = undefined;
    this.host = undefined;
  }

  /** 能点“应用”。 */
  get applicable(): boolean {
    return this.kind !== CommandPlanKind.NO_NODES;
  }
}

export class CommandPlanner {
  private engine: ZephyrEngine;

  constructor(engine: ZephyrEngine) {
    this.engine = engine;
  }

  /** 像域名或 IP（§16.d 末行：测试规则）。 */
  static looksLikeHost(input: string): boolean {
    const s = input.trim().toLowerCase();
    if (s.length < 3 || s.indexOf(' ') >= 0) {
      return false;
    }
    const dot = s.indexOf('.');
    if (dot <= 0 || dot === s.length - 1 || s.endsWith('.')) {
      return false;
    }
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      const ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c === '.' || c === '-' || c === ':';
      if (!ok) {
        return false;
      }
    }
    return true;
  }

  async plan(p: ParsedCommand): Promise<CommandPlan | undefined> {
    const svc = p.service;
    if (svc === undefined) {
      return undefined;
    }
    let scenes: Scene[] = [];
    try {
      scenes = this.engine.scenes().value;
    } catch (e) {
      scenes = [];
    }
    const scene = scenes.find((s: Scene) => s.kind === svc.kind);
    if (p.act === CommandAct.DIRECT) {
      if (svc.host === undefined) {
        return undefined;
      }
      const d = new CommandPlan(CommandPlanKind.DIRECT);
      d.serviceName = svc.name;
      d.host = svc.host;
      d.scene = scene ?? scenes.find((s: Scene) => s.kind === SceneKind.OTHER);
      return d;
    }
    if (p.act !== undefined) {
      return undefined; // 4K：§15.h 待移植
    }
    const rg = p.region;
    if (rg === undefined || scene === undefined || svc.kind === SceneKind.OTHER) {
      return undefined;
    }
    let pool: NodeSummary[] = [];
    try {
      pool = await this.engine.sceneCandidates(scene.id, rg.code);
    } catch (e) {
      pool = [];
    }
    pool = pool.slice().sort((a: NodeSummary, b: NodeSummary) =>
      (a.latencyMs ?? Number.MAX_SAFE_INTEGER) - (b.latencyMs ?? Number.MAX_SAFE_INTEGER));
    const plan = new CommandPlan(pool.length > 0 ? CommandPlanKind.EXIT : CommandPlanKind.NO_NODES);
    plan.serviceName = svc.name;
    plan.isSceneWord = svc.isSceneWord;
    plan.scene = scene;
    plan.appId = svc.appId;
    plan.regionCode = rg.code;
    plan.available = pool.length;
    if (pool.length === 0) {
      return plan;
    }
    const best = pool[0];
    plan.node = best;
    plan.previousSelected = scene.selected.id;
    const appId = svc.appId;
    const pin: SceneException | undefined = appId !== undefined ?
      scene.exceptions.find((x: SceneException) => x.appId === appId) : undefined;
    const currentRegion: string | undefined = pin !== undefined ? pin.node.region :
      (scene.selected.id >= 0 ? scene.selected.region : undefined);
    if (currentRegion !== rg.code) {
      try {
        const x = await this.engine.previewSceneChange(scene.id, best.id);
        if (pin !== undefined) {
          x.fromRegion = pin.node.region;
          x.fromIp = undefined;
        }
        plan.change = x;
      } catch (e) {
        plan.change = undefined;
      }
    }
    if (pin !== undefined) {
      plan.previousPin = pin.node.id;
      if (pin.node.id !== best.id) {
        plan.releasesPin = pin.node.name;
      }
    }
    return plan;
  }

  async planText(input: string): Promise<CommandPlan | undefined> {
    return this.plan(CommandParser.parse(input));
  }

  /** 执行（预览过的）计划；返回撤销函数。 */
  async apply(plan: CommandPlan): Promise<() => Promise<void>> {
    const engine = this.engine;
    if (plan.kind === CommandPlanKind.DIRECT && plan.host !== undefined) {
      const host = plan.host;
      await engine.overrideHost(host, TraceTarget.DIRECT, undefined, true);
      return async () => {
        await engine.overrideHost(host, TraceTarget.UNCHANGED, undefined, true);
      };
    }
    const scene = plan.scene;
    const node = plan.node;
    if (plan.kind !== CommandPlanKind.EXIT || scene === undefined || node === undefined) {
      throw new Error('not applicable');
    }
    const appId = plan.appId;
    if (appId !== undefined && !plan.isSceneWord) {
      const prev = plan.previousPin;
      await engine.setSceneException(scene.id, appId, node.id);
      return async () => {
        await engine.setSceneException(scene.id, appId, prev);
      };
    }
    const previous = plan.previousSelected;
    await engine.applySceneChange(scene.id, node.id);
    return async () => {
      if (previous !== undefined && previous >= 0) {
        await engine.applySceneChange(scene.id, previous);
      }
    };
  }
}
