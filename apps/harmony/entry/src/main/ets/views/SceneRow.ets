/*
 * 首页场景行（U5，对照 Android SceneCard.SceneRow，简化）：
 * - 左：场景名 + “N 个可用” / 服务不可用 / 订阅分组；右：地区徽标 + 当前节点名，下方例外（钉住）行。
 * - 左右滑（PanGesture 水平）：每 42vp 跨一个地区槽，徽标与节点实时变，跨槽轻触感；松手停在别的槽 → onPick，
 *   由首页出“更改出口 IP？”确认卡。订阅分组来源、只有一个地区时不可滑。滑动时底部显示槽位轨道。
 * - 读屏：整行一个焦点，朗读“场景 · 节点”；滑动换地区的无障碍替代（自定义动作）待 M1-18 无障碍走查。
 */
import { GestureLock } from '../common/GestureLock';
import { HapticKind, Haptics } from '../app/Haptics';
import { AppServices } from '../app/AppServices';
import { SceneSlots } from '../app/SceneSlots';
import { Labels } from '../common/Labels';
import { ZTheme } from '../common/Theme';
import { NodeSummary, Scene, SceneSource, ServiceHealth } from '../engine/Model';

@ComponentV2
export struct SceneRow {
  @Param @Require scene: Scene;
  /** 确认卡打开时显示待切换的节点。 */
  @Param pendingNode: NodeSummary | undefined = undefined;
  @Param divider: boolean = true;
  @Event onPick: (node: NodeSummary) => void = (node: NodeSummary) => {};
  @Event onScrubStart: () => void = () => {};

  @Local slots: NodeSummary[] = [];
  @Local scrubbing: boolean = false;
  @Local idx: number = 0;
  @Local theme: ZTheme = ZTheme.shared();
  private loadedFor: string = '';

  aboutToAppear(): void {
    this.loadSlots();
  }

  @Monitor('scene')
  onSceneChanged(): void {
    this.loadSlots();
  }

  private loadSlots(): void {
    const s = this.scene;
    const key = s.id + ':' + String(s.selected.id) + ':' + (s.nodeFilter ?? '');
    if (key === this.loadedFor) {
      return;
    }
    this.loadedFor = key;
    AppServices.get().engine.sceneCandidates(s.id).then((pool: NodeSummary[]) => {
      if (this.loadedFor === key) {
        this.slots = SceneSlots.build(s, pool);
        this.idx = SceneSlots.currentIndex(s, this.slots);
      }
    }).catch(() => {
      this.slots = [s.selected];
      this.idx = 0;
    });
  }

  private shown(): NodeSummary {
    if (this.scrubbing && this.idx < this.slots.length) {
      return this.slots[this.idx];
    }
    return this.pendingNode ?? this.scene.selected;
  }

  private subtitle(): ResourceStr {
    const down = this.scene.services.filter((h: ServiceHealth) => !h.ok);
    if (down.length > 0) {
      return $r('app.string.home_scene_services_down', down.map((h: ServiceHealth) => h.name).join('、'));
    }
    if (this.scene.source === SceneSource.SUBSCRIPTION_GROUP) {
      return $r('app.string.common_source_group');
    }
    return $r('app.plural.common_available_count', this.scene.available, this.scene.available);
  }

  private pinLine(): ResourceStr | undefined {
    const up = this.scene.services.filter((h: ServiceHealth) => h.ok);
    if (this.scene.services.some((h: ServiceHealth) => !h.ok) && up.length > 0) {
      return $r('app.string.home_scene_services_ok', up.map((h: ServiceHealth) => h.name).join('、'));
    }
    if (this.scene.exceptions.length > 0) {
      const e = this.scene.exceptions[0];
      return $r('app.string.home_pin_line', e.app, e.node.name);
    }
    return this.scene.note;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(Labels.sceneName(this.scene))
            .fontSize(17)
            .fontColor($r('app.color.screen_t1'))
            .maxLines(1)
          Text(this.subtitle())
            .fontSize(13)
            .fontColor(this.scene.services.some((h: ServiceHealth) => !h.ok) ? $r('app.color.screen_red')
              : $r('app.color.screen_t3'))
            .maxLines(1)
        }
        .layoutWeight(4)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 5 }) {
          Row({ space: 10 }) {
            Text(this.shown().region)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontFamily('monospace')
              .fontColor(this.scrubbing ? $r('app.color.screen_on_primary') : $r('app.color.screen_t1'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(this.scrubbing ? this.theme.accentColor() : $r('app.color.screen_s3'))
            Text(this.shown().name)
              .fontSize(15)
              .fontColor($r('app.color.screen_t1'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
          }
          .justifyContent(FlexAlign.End)
          if (this.pinLine() !== undefined) {
            Text(this.pinLine())
              .fontSize(12)
              .fontColor($r('app.color.screen_t3'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(6)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 15, bottom: 15 })

      if (this.scrubbing) {
        Row({ space: 3 }) {
          ForEach(this.slots, (n: NodeSummary, k: number) => {
            Row()
              .layoutWeight(1)
              .height(3)
              .borderRadius(2)
              .backgroundColor(k === this.idx ? this.theme.accentColor() : $r('app.color.screen_hl2'))
          }, (n: NodeSummary, k: number) => String(k))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })
      }
      if (this.divider) {
        Divider().strokeWidth(0.5).color($r('app.color.screen_hl')).margin({ left: 16 })
      }
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityText(this.scene.name + ' · ' + this.scene.selected.name)
    // 手指按在行上就加锁（不论手势竞争谁赢），抬起 / 取消后 350 ms 解锁：期间根 Tabs 拒绝切 tab。
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        GestureLock.hold();
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        GestureLock.release();
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart(() => {
          GestureLock.hold();
          if (!SceneSlots.swipeable(this.scene, this.slots)) {
            return;
          }
          this.idx = SceneSlots.currentIndex(this.scene, this.slots);
          this.scrubbing = true;
          this.onScrubStart();
        })
        .onActionUpdate((e: GestureEvent) => {
          if (!this.scrubbing) {
            return;
          }
          const i = SceneSlots.indexAfter(SceneSlots.currentIndex(this.scene, this.slots), e.offsetX, this.slots.length);
          if (i !== this.idx) {
            this.idx = i;
            Haptics.play(HapticKind.SELECTION);
          }
        })
        .onActionEnd(() => {
          GestureLock.release();
          if (!this.scrubbing) {
            return;
          }
          this.scrubbing = false;
          const target = this.idx < this.slots.length ? this.slots[this.idx] : undefined;
          if (target !== undefined && target.id !== this.scene.selected.id) {
            this.onPick(target);
          } else {
            this.idx = SceneSlots.currentIndex(this.scene, this.slots);
          }
        })
        .onActionCancel(() => {
          GestureLock.release();
          this.scrubbing = false;
          this.idx = SceneSlots.currentIndex(this.scene, this.slots);
        })
    )
  }
}
