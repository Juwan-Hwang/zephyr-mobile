// 节点页 UIKit 手动布局的 RTL 镜像（D-P2-12）。

import UIKit
import XCTest
@testable import ZephyrFeatures

@MainActor
final class RTLLayoutTests: XCTestCase {
    func testMirrorFlipsHorizontallyOnly() {
        let r = RTLLayout.mirror(CGRect(x: 20, y: 5, width: 100, height: 30), in: 400)
        XCTAssertEqual(r, CGRect(x: 280, y: 5, width: 100, height: 30))
    }

    func testMirrorIsInvolution() {
        let r = CGRect(x: 13, y: 0, width: 57, height: 44)
        XCTAssertEqual(RTLLayout.mirror(RTLLayout.mirror(r, in: 375), in: 375), r)
    }

    func testViewHelpersFollowLayoutDirection() {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        let r = CGRect(x: 10, y: 0, width: 50, height: 44)
        v.semanticContentAttribute = .forceLeftToRight
        XCTAssertFalse(v.isRTL)
        XCTAssertEqual(v.rtl(r, in: 300), r)
        XCTAssertEqual(v.trailingAlignment, .right)
        v.semanticContentAttribute = .forceRightToLeft
        XCTAssertTrue(v.isRTL)
        XCTAssertEqual(v.rtl(r, in: 300), CGRect(x: 240, y: 0, width: 50, height: 44))
        XCTAssertEqual(v.trailingAlignment, .left)
    }
}
