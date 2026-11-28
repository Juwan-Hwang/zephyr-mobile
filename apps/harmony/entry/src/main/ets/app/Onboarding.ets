/*
 * 首次引导（M1-16；对照 Android ui/onboarding OnboardingScreen / MainActivity）：
 * - 何时显示：真实引擎且没走完引导。演示（Mock）引擎不显示，同 Android `!AppGraph.demo`；
 *   设置 › 关于里的“显示引导页（演示）”通过 request 流手动打开，便于云调试验证。
 * - 第 2 步“简单 / 优选”：简单 = 每个场景跟订阅自己的分组；优选 = Zephyr 从检测过的节点里挑（SceneSource.AUTO）。
 *   全新安装还没用过任何出口，所以这里改 AI 场景来源不算需要确认的出口变更。
 */
import { Scene, SceneSource } from '../engine/Model';
import { StateStream } from '../engine/Stream';
import { ZephyrEngine } from '../engine/ZephyrEngine';

export class Onboarding {
  /** 递增即请求显示引导页（演示入口）。 */
  static readonly request: StateStream<number> = new StateStream<number>(0);

  /** 引导页在屏时由它处理系统返回（Index.onBackPress 转发）。 */
  static backHandler: (() => boolean) | undefined = undefined;

  static shouldShow(engineKind: string, onboarded: boolean): boolean {
    return engineKind !== 'mock' && !onboarded;
  }

  static sourceFor(simple: boolean): SceneSource {
    return simple ? SceneSource.SUBSCRIPTION_GROUP : SceneSource.AUTO;
  }

  /** 把来源不同的场景都改过去；单个失败忽略（同 Android runCatching）。 */
  static async applyMode(engine: ZephyrEngine, simple: boolean): Promise<number> {
    const source = Onboarding.sourceFor(simple);
    let changed = 0;
    for (const sc of engine.scenes().value.filter((s: Scene) => s.source !== source)) {
      try {
        await engine.setSceneSource(sc.id, source);
        changed++;
      } catch (e) {
        // 忽略
      }
    }
    return changed;
  }
}
