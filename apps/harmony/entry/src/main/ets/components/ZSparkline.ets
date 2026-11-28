/*
 * 流量曲线（对照 Android design ZSparkline、iOS Home/TrafficChart）：单调三次插值的下行速率曲线 + 自上而下渐隐的面积填充 +
 * 最新点圆点；样本少于 2 个（或 idle = true，未连接）时画原型的虚线基线（3 vp、点划 2/8，位于 94 % 高度）。
 * 几何在 app/HomeModel SparkGeometry（纯逻辑，有单测）。时间轴不随 RTL 镜像：最新样本始终在右（同 Android）。
 */
import { SparkGeometry, SparkSegment, SparkShape } from '../app/HomeModel';
import { TodayArt } from '../app/TodayArt';

@ComponentV2
export struct ZSparkline {
  @Param values: number[] = [];
  /** '#AARRGGBB' 或 '#RRGGBB'。 */
  @Param color: string = '#FF007AFF';
  @Param idle: boolean = false;
  @Param dark: boolean = false;
  @Param description: string = '';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @Monitor('values', 'idle', 'dark', 'color')
  onData(): void {
    this.draw();
  }

  private rgb(): string {
    // withAlpha 需要 '#RRGGBB'。
    return this.color.length === 9 ? '#' + this.color.substring(3) : this.color;
  }

  private draw(): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    c.clearRect(0, 0, w, h);
    const shape: SparkShape | undefined = this.idle ? undefined : SparkGeometry.build(this.values, w, h);
    if (shape === undefined) {
      this.baseline(w, h);
      return;
    }
    const rgb = this.rgb();
    // 面积
    c.beginPath();
    c.moveTo(shape.start.x, shape.start.y);
    shape.segments.forEach((s: SparkSegment) => c.bezierCurveTo(s.c1.x, s.c1.y, s.c2.x, s.c2.y, s.to.x, s.to.y));
    c.lineTo(w, h);
    c.lineTo(0, h);
    c.closePath();
    const g = c.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, TodayArt.withAlpha(rgb, 0.28));
    g.addColorStop(1, TodayArt.withAlpha(rgb, 0));
    c.fillStyle = g;
    c.fill();
    // 线
    c.beginPath();
    c.moveTo(shape.start.x, shape.start.y);
    shape.segments.forEach((s: SparkSegment) => c.bezierCurveTo(s.c1.x, s.c1.y, s.c2.x, s.c2.y, s.to.x, s.to.y));
    c.lineWidth = 2.2;
    c.lineCap = 'round';
    c.lineJoin = 'round';
    c.strokeStyle = TodayArt.withAlpha(rgb, 1);
    c.stroke();
    // 最新点
    c.beginPath();
    c.arc(Math.min(shape.head.x, w - 3.5), shape.head.y, 3.5, 0, Math.PI * 2);
    c.fillStyle = TodayArt.withAlpha(rgb, 1);
    c.fill();
  }

  private baseline(w: number, h: number): void {
    const c = this.ctx;
    const y = h * 0.94;
    c.beginPath();
    c.setLineDash([2, 8]);
    c.lineWidth = 3;
    c.lineCap = 'round';
    c.strokeStyle = this.dark ? TodayArt.withAlpha('#FFFFFF', 0.12) : TodayArt.withAlpha('#000000', 0.15);
    c.moveTo(1.5, y);
    c.lineTo(w - 1.5, y);
    c.stroke();
    c.setLineDash([]);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => this.draw())
      .onAreaChange(() => this.draw())
      .accessibilityText(this.description)
      .accessibilityLevel(this.idle ? 'no' : 'yes')
  }
}
