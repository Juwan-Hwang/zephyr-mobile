// NodeListRepresentable — 把 UIKit 的 NodeListView 挂进 SwiftUI。
// update 只传“结果代数 + 强调色”，SwiftUI 重算不会触发列表重载（generation 不变即忽略）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct NodeListRepresentable: UIViewRepresentable {
    let model: NodesModel
    let rowMap: NodeRowMap
    let generation: Int
    let accent: Color
    var onSelect: (NodeSummary) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> NodeListView {
        let v = NodeListView(store: model.store)
        model.listView = v
        return v
    }

    func updateUIView(_ v: NodeListView, context: Context) {
        v.onSelect = onSelect
        v.setAccent(accent, reduceMotion: reduceMotion)
        v.apply(rowMap: rowMap, generation: generation)
    }

    static func dismantleUIView(_ v: NodeListView, coordinator: ()) {
        v.store.onPageLoaded = nil
        v.store.onLatencyChanged = nil
    }
}
