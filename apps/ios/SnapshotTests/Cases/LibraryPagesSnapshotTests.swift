// 资料库下钻页：节点（原型 20 / 21 搜索）、规则（原型 22 / 23 已拦截）。
// 这两页在 `.task` 里异步拉数据、强调色从引擎设置读取，所以每个变体用全新的冻结 MockEngine，并给足 settle。

import SwiftUI
import XCTest
import ZephyrDesign
import ZephyrFeatures
import ZephyrKit

@MainActor
final class LibraryPagesSnapshotTests: XCTestCase {

    /// 页面在 App 里是 push 进 NavigationStack 的（有导航栏按钮），快照保持同样的容器。
    private func pushed<Content: View>(_ content: Content) -> some View {
        NavigationStack { content }
    }

    func testNodes() async {
        await zAssertSnapshots(named: "nodes", variants: ZSnapshotVariant.standardPlusAccent(.orange), settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(NodesView(engine: engine))
        }
    }

    func testNodesSearch() async {
        await zAssertSnapshots(named: "nodes-search", variants: [.dark, .light], settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(NodesView(engine: engine, query: "东京 IPLC"))
        }
    }

    func testNodesNoResult() async {
        await zAssertSnapshots(named: "nodes-empty", variants: [.dark], settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(NodesView(engine: engine, query: "zzzz-不存在的节点"))
        }
    }

    func testRules() async {
        await zAssertSnapshots(named: "rules", variants: ZSnapshotVariant.standardPlusAccent(.pink, light: true), settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(RulesView(engine: engine))
        }
    }

    /// 原型 23：测试一个会被拦截的域名，命中链停在拦截层。
    func testRulesBlocked() async {
        await zAssertSnapshots(named: "rules-blocked", variants: [.dark, .light], settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(RulesView(engine: engine, query: "ads.doubleclick.net"))
        }
    }
}
