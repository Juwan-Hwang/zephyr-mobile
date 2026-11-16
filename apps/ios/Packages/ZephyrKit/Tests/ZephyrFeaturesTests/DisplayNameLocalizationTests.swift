// D-P2-12：核心给的中文显示名在界面层的本地化（内置场景名、节点分区地区名）。
// 单测 ZL.bundle 为 nil（中文），只验证回落与“自定义不翻译”的语义；译文本身由快照 ar / ja 变体验收。

import XCTest
@testable import ZephyrFeatures
import ZephyrKit

final class DisplayNameLocalizationTests: XCTestCase {
    func testBuiltinSceneNamesFallBackToChineseWithoutBundle() {
        XCTAssertEqual(Scene.displayName("视频", kind: .video), "视频")
        XCTAssertEqual(Scene.displayName("AI", kind: .ai), "AI")
    }

    func testCustomSceneNamesAreNeverTranslated() {
        // 自定义场景名恰好与目录键相同也原样显示（用户起的名字）。
        XCTAssertEqual(Scene.displayName("视频", kind: .custom), "视频")
        XCTAssertEqual(Scene.displayName("我的游戏", kind: .custom), "我的游戏")
    }

    func testSectionRegionNameKeepsCoreNameInChinese() {
        XCTAssertNil(ZL.bundle)
        XCTAssertEqual(NodeRowMap.displayRegionName("美国", code: "US"), "美国")
        let map = NodeRowMap(sections: [("US", "美国", 3), ("JP", "日本", 2)])
        XCTAssertEqual(map.sections.map(\.name), ["美国", "日本"])
    }
}
