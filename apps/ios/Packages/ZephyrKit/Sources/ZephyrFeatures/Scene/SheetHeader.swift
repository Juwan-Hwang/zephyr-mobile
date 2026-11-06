// Sheet 顶栏（原型 `.sh-top`）：左标题（17/500），右"完成"。待替换为 D 的 ZSheet 头部。

import SwiftUI
import ZephyrDesign

struct SheetHeader: View {
    let title: String
    var onDone: (() -> Void)?

    var body: some View {
        HStack {
            Text(verbatim: title)
                .zType(.headline).fontWeight(.medium)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let onDone {
                Button(action: onDone) {
                    Text(verbatim: "完成")
                        .zType(.body)
                        .foregroundStyle(ZTokens.Colors.textSecondary)
                        .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .light))
            }
        }
        .padding(.leading, HMetrics.homeInset)
        .padding(.trailing, ZTokens.Space.n4)
        .padding(.top, ZTokens.Space.n5)
    }
}

#Preview {
    SheetHeader(title: "AI") {}
        .zPageBackground()
}
