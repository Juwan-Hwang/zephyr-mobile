// SubscriptionsAllView — 流量卡最后一行“其他 212 个 ›”进入的完整列表：可搜索，左滑更新 / 删除，下拉更新全部。
// 与订阅页共用 SubscriptionsModel（同一条订阅流、同一套确认与吐司）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

@MainActor
struct SubscriptionsAllView: View {
    let model: SubscriptionsModel
    @State private var query = ""

    var body: some View {
        List {
            Section {
                ForEach(filtered) { sub in
                    ZSettingsRow(verbatim: sub.name, subtitle: model.detail(sub), accessory: .none)
                        .subscriptionRow(sub, model: model)
                }
            } footer: {
                Text("\(ZFormat.count(Int64(filtered.count))) 个订阅 · \(ZFormat.count(nodeCount)) 个节点")
                    .zType(.footnote)
                    .foregroundStyle(ZColor.t3)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, PageMetrics.margin, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .zPageBackground()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("搜索订阅"))
        .overlay {
            if filtered.isEmpty && !query.isEmpty {
                ZEmptyState("无结果", message: "没有与“\(query)”匹配的订阅")
            }
        }
        .refreshable { await model.refreshAll() }
        .subscriptionsPresentations(model)
        .navigationTitle(Text("全部订阅"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [Subscription] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.subscriptions }
        return model.subscriptions.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var nodeCount: Int64 { filtered.reduce(0) { $0 + $1.nodeCount } }
}

#if DEBUG
#Preview {
    let model = SubscriptionsModel(engine: MockEngine(seed: 0, clock: .frozen941), now: { MockClock.frozen941.now() })
    return NavigationStack { SubscriptionsAllView(model: model) }
        .task { await model.start() }
        .preferredColorScheme(.dark)
}
#endif
