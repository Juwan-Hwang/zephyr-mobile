// 订阅（原型 24）、设置（25）、资料库（13）、引导（01–03）快照。

import SwiftUI
import XCTest
import ZephyrDesign
import ZephyrFeatures
import ZephyrKit
import ZephyrMock

@MainActor
final class L2PagesSnapshotTests: XCTestCase {

    private func pushed<Content: View>(_ content: Content) -> some View {
        NavigationStack { content }
    }

    func testSubscriptions() async {
        await zAssertSnapshots(named: "subscriptions", variants: ZSnapshotVariant.standardPlusAccent(.green) + ZSnapshotVariant.languages, settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(SubscriptionsView(engine: engine, now: { MockClock.prototypeMillis }))
        }
    }

    func testSettings() async {
        await zAssertSnapshots(named: "settings", variants: ZSnapshotVariant.standardPlusAccent(.orange, light: true) + ZSnapshotVariant.languages, settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return pushed(SettingsView(engine: engine))
        }
    }

    func testLibrarySheet() async {
        await zAssertSnapshots(named: "library", variants: ZSnapshotVariant.standardPlusAccent(.pink), settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(accent: variant.accent)
            return LibrarySheet(engine: engine, onOpen: { _ in })
        }
    }

    /// 引导从未连接、无订阅的引擎开始（原型 01 第一次打开）。
    func testOnboarding() async {
        await zAssertSnapshots(named: "onboarding", variants: ZSnapshotVariant.standardPlusAccent(.green, light: true) + ZSnapshotVariant.languages, settle: 0.8) { variant in
            let engine = await SnapshotFixtures.engine(connected: false, accent: variant.accent)
            return OnboardingView(engine: engine, onFinish: {})
        }
    }
}
