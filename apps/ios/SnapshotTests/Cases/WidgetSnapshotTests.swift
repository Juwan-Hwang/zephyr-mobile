// 主屏 / 锁屏小组件（原型 shots/hs.png、shots/lock.png）。
// Widgets/Views 直接编进本测试 target（见 project.yml），这里不依赖 WidgetKit 运行时：
// 用与系统一致的尺寸、圆角和背景包一层，模拟小组件容器。iPhone 16：小号 170×170、中号 364×170。

import SwiftUI
import XCTest
import ZephyrDesign

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    /// 外边留白，让圆角与背景在图里看得见。
    static let margin: CGFloat = 12

    private func canvas(_ size: CGSize) -> ZSnapshotLayout {
        .fixed(CGSize(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2))
    }

    /// 系统小组件容器：内边距 16（≈ ZTokens.Space.n5）、bgElevated、连续圆角。
    private func homeWidget<Content: View>(_ size: CGSize, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(ZTokens.Space.n5)
            .frame(width: size.width, height: size.height)
            .background(ZTokens.Colors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 锁屏配件：系统以单色/半透明渲染在壁纸上，这里固定黑底白字（与锁屏一致，不随深浅变化）。
    private func accessory<Content: View>(_ size: CGSize, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    // MARK: 主屏

    func testStatusSmall() async {
        let states: [(String, SharedState)] = [
            ("connected", SnapshotFixtures.connected),
            ("disconnected", SnapshotFixtures.disconnected),
            ("failed", SnapshotFixtures.failed),
            ("global", SnapshotFixtures.global),
        ]
        for (name, state) in states {
            let variants: [ZSnapshotVariant] = name == "connected" ? ZSnapshotVariant.standard : [.dark, .light]
            for variant in variants {
                await zAssertSnapshot(of: homeWidget(Self.small) { StatusSmallView(state: state) },
                                      named: "status-small-\(name)-\(variant.name)", variant: variant, layout: canvas(Self.small))
            }
        }
    }

    func testUsageSmall() async {
        for variant in ZSnapshotVariant.standardPlusAccent(.green) {
            let state = SnapshotFixtures.accent(variant.accent)
            await zAssertSnapshot(of: homeWidget(Self.small) { UsageSmallView(state: state, now: SnapshotFixtures.now) },
                                  named: "usage-small-\(variant.name)", variant: variant, layout: canvas(Self.small))
        }
        await zAssertSnapshot(of: homeWidget(Self.small) { UsageSmallView(state: SnapshotFixtures.empty, now: SnapshotFixtures.now) },
                              named: "usage-small-empty-dark", variant: .dark, layout: canvas(Self.small))
    }

    func testStatusMedium() async {
        for variant in ZSnapshotVariant.standardPlusAccent(.pink, light: true) {
            let state = SnapshotFixtures.accent(variant.accent)
            await zAssertSnapshot(of: homeWidget(Self.medium) { StatusMediumView(state: state, now: SnapshotFixtures.now) },
                                  named: "status-medium-\(variant.name)", variant: variant, layout: canvas(Self.medium))
        }
    }

    func testScenesMedium() async {
        for variant in ZSnapshotVariant.standard {
            await zAssertSnapshot(of: homeWidget(Self.medium) { ScenesMediumView(state: SnapshotFixtures.connected) },
                                  named: "scenes-medium-\(variant.name)", variant: variant, layout: canvas(Self.medium))
        }
        await zAssertSnapshot(of: homeWidget(Self.medium) { ScenesMediumView(state: SnapshotFixtures.edgyScenes) },
                              named: "scenes-medium-edge-dark", variant: .dark, layout: canvas(Self.medium))
        await zAssertSnapshot(of: homeWidget(Self.medium) { ScenesMediumView(state: SnapshotFixtures.empty) },
                              named: "scenes-medium-empty-light", variant: .light, layout: canvas(Self.medium))
    }

    // MARK: 锁屏

    func testLockCircular() async {
        let size = CGSize(width: 76, height: 76)
        for (name, state) in [("connected", SnapshotFixtures.connected), ("disconnected", SnapshotFixtures.disconnected)] {
            for variant in [ZSnapshotVariant.dark, .darkAX5] {
                await zAssertSnapshot(of: accessory(size) { LockCircularView(state: state) },
                                      named: "lock-circular-\(name)-\(variant.name)", variant: variant, layout: canvas(size))
            }
        }
    }

    func testLockRectangular() async {
        let size = CGSize(width: 172, height: 76)
        for (name, state) in [("connected", SnapshotFixtures.connected), ("disconnected", SnapshotFixtures.disconnected)] {
            for variant in [ZSnapshotVariant.dark, .darkAX5] {
                await zAssertSnapshot(of: accessory(size) { LockRectangularView(state: state) },
                                      named: "lock-rect-\(name)-\(variant.name)", variant: variant, layout: canvas(size))
            }
        }
    }

    func testLockInline() async {
        let size = CGSize(width: 260, height: 26)
        for (name, state) in [("connected", SnapshotFixtures.connected), ("disconnected", SnapshotFixtures.disconnected)] {
            await zAssertSnapshot(of: accessory(size) { LockInlineView(state: state) },
                                  named: "lock-inline-\(name)-dark", variant: .dark, layout: canvas(size))
        }
    }

    // MARK: 零件

    func testWidgetParts() async {
        let parts = VStack(alignment: .leading, spacing: ZTokens.Space.n4) {
            HStack(spacing: ZTokens.Space.n5) {
                PowerButton(isOn: true)
                PowerButton(isOn: false)
                WidgetMark().frame(height: ZTokens.Space.n6)
            }
            HStack(spacing: ZTokens.Space.n3) {
                RegionBadge(region: "JP")
                RegionBadge(region: "hk")
                RegionBadge(region: "TW", prominent: true)
                LatencyText(ms: 61)
                LatencyText(ms: -1)
                LatencyText(ms: nil)
            }
            UsageBars(hourly: SnapshotFixtures.connected.usage.hourly, accent: ZTokens.Accent.blue.color)
                .frame(width: 200, height: 60)
        }
        .padding(ZTokens.Space.n5)
        .foregroundStyle(ZTokens.Colors.textPrimary)
        for variant in ZSnapshotVariant.standard {
            await zAssertSnapshot(of: parts, named: "parts-\(variant.name)", variant: variant, layout: .fitWidth(393))
        }
    }
}
