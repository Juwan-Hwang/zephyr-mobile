// 首页速率（原型 `.spd`：下载 56/200 大数字 + “MB/s ↓”（↓ 下载蓝），下一行 “192 KB/s ↑”（↑ 上传红）13 号 t3）。
// 未连接时淡出数字、显示 idle 说明（`.idle` 14 号 t3），400ms 内交叉淡变。
// 数值用 ZFormat.rate(Int64) 的结果：`ZRateText(ZFormat.rate(bps))`。

import SwiftUI

/// 已格式化的速率（值 + 单位），如 ("2.8", "MB/s")。
public struct ZRateText: Sendable, Equatable {
    public var value: String
    public var unit: String

    public init(_ value: String, unit: String) {
        self.value = value
        self.unit = unit
    }

    /// 直接接 `ZFormat.rate(_:)` 的返回值。
    public init(_ pair: (value: String, unit: String)) {
        self.value = pair.value
        self.unit = pair.unit
    }
}

public struct ZTrafficStat: View {
    private let down: ZRateText
    private let up: ZRateText
    private let isActive: Bool
    private let idleMessage: LocalizedStringKey?

    public init(down: ZRateText, up: ZRateText, isActive: Bool = true, idleMessage: LocalizedStringKey? = nil) {
        self.down = down
        self.up = up
        self.isActive = isActive
        self.idleMessage = idleMessage
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                ZBigNumber(down.value, unit: nil, size: .large)
                    .modifier(ZTrailingUnit(text: down.unit, arrow: "↓", arrowColor: ZTokens.Colors.colorDownload))
                HStack(spacing: ZTokens.Space.n1) {
                    Text(verbatim: up.value).foregroundStyle(ZTokens.Colors.textSecondary)
                    Text(verbatim: up.unit).foregroundStyle(ZTokens.Colors.textTertiary)
                    Text(verbatim: "↑").foregroundStyle(ZTokens.Colors.colorUpload)
                }
                .zType(.footnote, monospacedDigits: true)
            }
            .opacity(isActive ? 1 : 0)

            if let idleMessage {
                Text(idleMessage)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ZTokens.Space.n6)
                    .opacity(isActive ? 0 : 1)
            }
        }
        .animation(ZMotion.standard, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

extension ZTrafficStat {
    private var spoken: Text {
        if isActive {
            return Text(verbatim: "下载 \(down.value) \(down.unit)，上传 \(up.value) \(up.unit)")
        }
        if let idleMessage { return Text(idleMessage) }
        return Text(verbatim: "未连接")
    }
}

/// 大数字右侧的 “MB/s ↓”（基线对齐，13 号 t3，箭头着色）。
private struct ZTrailingUnit: ViewModifier {
    let text: String
    let arrow: String
    let arrowColor: Color

    func body(content: Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                content
                unit
            }
            VStack(alignment: .leading, spacing: 0) {
                content
                unit
            }
        }
    }

    private var unit: some View {
        HStack(spacing: ZTokens.Space.n1) {
            Text(verbatim: text).foregroundStyle(ZTokens.Colors.textTertiary)
            Text(verbatim: arrow).foregroundStyle(arrowColor)
        }
        .zType(.footnote)
    }
}

#if DEBUG
private struct ZTrafficSample: View {
    @State var on = true
    var body: some View {
        ZTrafficStat(down: ZRateText("2.8", unit: "MB/s"), up: ZRateText("192", unit: "KB/s"),
                     isActive: on, idleMessage: "连接后，这里显示实时速率。")
        ZButton(LocalizedStringKey(on ? "断开" : "连接"), kind: .ghost) { on.toggle() }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZTrafficSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZTrafficSample() } }
#Preview("强调色") { ZAccentMatrix { ZTrafficStat(down: ZRateText("38.4", unit: "MB/s"), up: ZRateText("1.2", unit: "MB/s")) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZTrafficSample() } }
