// SubscriptionsView — 订阅页（原型 24）。
//
//   订阅 / 214 个 · 每 12 小时更新
//   [diff 卡] Nebula Cloud 已更新 · +1,204 −318 0 · 覆写已保留 · 场景池已重新检测
//   流量 · 本月：有流量信息的订阅（名称、节点数 · 到期、用量条、剩余）+ “其他 212 个 ›”
//   更新：自动更新（每 n 小时 ›）/ 仅在 Wi‑Fi 下更新 / 更新前显示更改
//
// List（insetGrouped，卡片底）以便左滑“更新 / 删除”；下拉 = 更新全部；右上“+” = 四种导入方式。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

@MainActor
public struct SubscriptionsView: View {
    @State private var model: SubscriptionsModel
    @State private var importer: SubscriptionImporter
    @State private var importMethod: SubscriptionImportMethod?
    @State private var showsAll = false

    /// - Parameters:
    ///   - now: 当前时间（毫秒），用于“2 小时前”“26 天后到期”。App 传 `AppModel.now`；快照传冻结时钟。
    public init(engine: any ZephyrEngine, now: @escaping @Sendable () -> Int64 = { ZFormat.nowMillis() }) {
        _model = State(initialValue: SubscriptionsModel(engine: engine, now: now))
        _importer = State(initialValue: SubscriptionImporter(engine: engine))
    }

    public var body: some View {
        List {
            Section { header }
            if !model.subscriptions.isEmpty {
                Section { traffic } header: { ZSectionHeader("流量", trailing: ZL.tr("本月")).listRowInsets(EdgeInsets()) }
            } else if model.loaded {
                Section { empty }
            }
            Section { updateSettings } header: { ZSectionHeader("更新").listRowInsets(EdgeInsets()) }
        }
        .listStyle(.insetGrouped)
        // 分组标题自带原型 `.sec` 的内边距（左右 6 + 卡片 16 = 22、上 24 / 下 8），不再叠系统 header 内边距与分组间距（REVIEW L-P2-12）。
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, PageMetrics.margin, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .zPageBackground()
        .refreshable { await model.refreshAll() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { addMenu } }
        .subscriptionImportFlow(method: $importMethod, importer: importer) { model.didImport($0) }
        .subscriptionsPresentations(model, isActive: !showsAll)
        .navigationDestination(isPresented: $showsAll) { SubscriptionsAllView(model: model) }
        .task { await model.start() }
        .pageAccent(model.settings.settings)
    }

    // MARK: 页头 + diff 卡

    @ViewBuilder private var header: some View {
        PageHeader(title: "订阅", number: model.loaded ? ZFormat.count(Int64(model.subscriptions.count)) : nil,
                   unit: model.headerUnit, horizontalInset: ZTokens.Space.n2)
            .padding(.bottom, ZTokens.Space.n4)
            .clearListRow()
        if let sub = model.latestUpdate, let diff = sub.lastDiff {
            SubscriptionDiffCard(title: ZL.s("%@ 已更新", sub.name),
                                 trailing: sub.updatedAt.map { ZFormat.relative($0, now: model.now()) },
                                 diff: diff)
                .clearListRow()
        }
    }

    // MARK: 流量

    @ViewBuilder private var traffic: some View {
        ForEach(model.metered) { sub in
            ZProfileCard(name: sub.name, detail: model.detail(sub),
                         remaining: sub.remainingBytes.map(ZFormat.bytes),
                         usage: model.usage(sub), isWarning: model.isWarning(sub))
                .subscriptionRow(sub, model: model)
        }
        if !model.others.isEmpty {
            Button { showsAll = true } label: {
                ZSettingsRow(verbatim: ZL.s("其他 %@ 个", ZFormat.count(Int64(model.others.count))),
                             subtitle: ZL.s("%@ 个节点", ZFormat.count(model.othersNodeCount)))
            }
            .buttonStyle(ZRowButtonStyle())
            .zCardListRow()
        }
    }

    private var empty: some View {
        ZEmptyState("还没有订阅", message: "添加订阅后，节点与规则会出现在这里。", systemImage: "tray",
                    actionTitle: "添加订阅") { importMethod = .paste }
            .padding(.vertical, ZTokens.Space.n6)
            .clearListRow()
    }

    // MARK: 更新设置

    @ViewBuilder private var updateSettings: some View {
        let store = model.settings
        MenuPickerRow(title: "自动更新", options: Self.intervals,
                      selection: store.binding(\.autoUpdateHours, fallback: Self.defaultInterval))
            .zCardListRow()
        ZSettingsRow("仅在 Wi‑Fi 下更新", isOn: store.binding(\.updateOnWifiOnly, fallback: true))
            .zCardListRow()
        ZSettingsRow("更新前显示更改", subtitle: ZL.tr("先预览新增与移除的节点，确认后再更新"),
                     isOn: store.binding(\.showChangesBeforeUpdate, fallback: false))
            .zCardListRow()
    }

    static let defaultInterval: Int32 = 12
    static var intervals: [MenuOption<Int32>] { [6, 12, 24, 48].map { MenuOption(value: Int32($0), title: ZL.f("每 %lld 小时", Int64($0))) } }

    // MARK: 导入

    private var addMenu: some View {
        Menu {
            ForEach(SubscriptionImportMethod.allCases) { m in
                Button { importMethod = m } label: {
                    Label { Text(verbatim: m.title) } icon: { Image(systemName: m.systemImage) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
                .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
        }
        .accessibilityLabel(Text("添加订阅"))
    }
}

#if DEBUG
#Preview("订阅") {
    NavigationStack {
        SubscriptionsView(engine: MockEngine(seed: 0, clock: .frozen941), now: { MockClock.frozen941.now() })
    }
    .preferredColorScheme(.dark)
}

#Preview("浅色 · 粉色") {
    NavigationStack {
        SubscriptionsView(engine: MockEngine(seed: 0, clock: .frozen941), now: { MockClock.frozen941.now() })
    }
    .zAccent(.pink)
    .preferredColorScheme(.light)
}

#Preview("大字体 AX5") {
    NavigationStack {
        SubscriptionsView(engine: MockEngine(seed: 0, clock: .frozen941), now: { MockClock.frozen941.now() })
    }
    .environment(\.dynamicTypeSize, .accessibility5)
    .preferredColorScheme(.dark)
}
#endif
