// NodesEmptyState — 两种空态（#207 U31，对齐 Android NodesScreen）：
//   搜索词为空且没有任何节点 → “还没有节点 / 导入订阅后，节点会出现在这里。”+“添加订阅”（有宿主时）；
//   有搜索词但无结果（原型 .vempty）→ “无结果 / 没有与“xxx”匹配的节点”。

import SwiftUI
import ZephyrDesign

struct NodesEmptyState: View {
    var query: String
    /// 空库时“添加订阅”按钮的动作；nil 时不显示按钮（预览 / 快照没有宿主）。
    var onImport: (() -> Void)? = nil

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: ZTokens.Space.n2) {
            if trimmed.isEmpty {
                title("还没有节点")
                Text("导入订阅后，节点会出现在这里。")
                    .zType(.footnote)
                    .foregroundStyle(ZColor.t3)
                    .multilineTextAlignment(.center)
                if let onImport {
                    ZButton("添加订阅", kind: .ghost, action: onImport)
                        .padding(.top, ZTokens.Space.n3)
                }
            } else {
                title("无结果")
                Text("没有与“\(trimmed)”匹配的节点")
                    .zType(.footnote)
                    .foregroundStyle(ZColor.t3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: trimmed.isEmpty && onImport != nil ? .contain : .combine)
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .zType(.headline)
            .fontWeight(.regular)
            .foregroundStyle(ZTokens.Colors.screenT1)
    }
}

/// 查询失败（引擎报错）：此前 NodesModel.failed 没有任何 UI，列表停在骨架（REVIEW-Q1 L-P2-11）。
struct NodesErrorState: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: ZTokens.Space.n2) {
            Text("节点载入失败")
                .zType(.headline)
                .fontWeight(.regular)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Text("请检查网络后重试")
                .zType(.footnote)
                .foregroundStyle(ZColor.t3)
                .multilineTextAlignment(.center)
            ZButton("重试", kind: .ghost, action: onRetry)
                .padding(.top, ZTokens.Space.n3)
        }
        .padding(ZTokens.Space.n6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zPageBackground()
    }
}

#if DEBUG
#Preview("失败") {
    NodesErrorState {}
        .preferredColorScheme(.dark)
}

#Preview {
    NodesEmptyState(query: "火星")
        .zPageBackground()
        .preferredColorScheme(.dark)
}

#Preview("空库") {
    NodesEmptyState(query: "", onImport: {})
        .zPageBackground()
        .preferredColorScheme(.dark)
}
#endif
