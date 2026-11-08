// NodeCell 布局：协议列在常规字号下必须显示在延迟列左侧（原型 .vrow），大字体隐藏。

import SwiftUI
import UIKit
import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class NodeCellTests: XCTestCase {
    private func laidOut(category: UIContentSizeCategory) -> (NodeCell, NodeListStyle) {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let style = NodeListStyle.make(traits: traits, accent: .blue)
        let cell = NodeCell(frame: CGRect(x: 0, y: 0, width: 393, height: style.rowHeight))
        cell.configure(node: NodeSummary(id: 1, name: "洛杉矶 CN2 GIA IPLC 01", region: "US", protocol: "TUIC"),
                       latency: nil, highlights: [], style: style)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        return (cell, style)
    }

    func testProtocolColumnShownAtLargeSize() {
        let (cell, style) = laidOut(category: .large)
        XCTAssertFalse(style.isXL)
        XCTAssertFalse(cell.protocolLabel.isHidden)
        XCTAssertEqual(cell.protocolLabel.text, "TUIC")
        XCTAssertGreaterThan(cell.protocolLabel.frame.width, 10, "frame=\(cell.protocolLabel.frame)")
        XCTAssertGreaterThan(cell.protocolLabel.frame.minX, 100, "frame=\(cell.protocolLabel.frame)")
    }

    func testProtocolColumnHiddenAtAccessibilitySize() {
        let (cell, style) = laidOut(category: .accessibilityExtraExtraExtraLarge)
        XCTAssertTrue(style.isXL)
        XCTAssertTrue(cell.protocolLabel.isHidden)
    }
}
