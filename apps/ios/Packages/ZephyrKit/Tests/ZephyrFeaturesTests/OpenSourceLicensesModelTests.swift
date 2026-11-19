import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class OpenSourceLicensesModelTests: XCTestCase {
    private static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { u.deleteLastPathComponent() }
        return u
    }()

    /// 与 App 资源同名的三份文件放进临时目录，当作 bundle 读（project.yml 把仓库根这三份原样打进 App）。
    func testLoadsBundledFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["THIRD_PARTY_NOTICES.md", "THIRD_PARTY_LICENSES.txt", "LICENSE"] {
            try FileManager.default.copyItem(at: Self.repoRoot.appendingPathComponent(name), to: dir.appendingPathComponent(name))
        }
        let bundle = try XCTUnwrap(Bundle(path: dir.path))
        let model = OpenSourceLicensesModel(bundle: bundle)
        XCTAssertEqual(model.phase, .loading)
        await model.load()
        let n = try XCTUnwrap(model.notices)
        XCTAssertFalse(n.rust.isEmpty)
        XCTAssertFalse(n.go.isEmpty)
        XCTAssertNotNil(n.gplText)
        XCTAssertFalse(n.appLicense.isEmpty)
    }

    /// 资源缺失 → 失败态（页面仍显示源码获取方式）。
    func testMissingResourcesFail() async {
        let model = OpenSourceLicensesModel(bundle: Bundle(for: Self.self))
        await model.load()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertNil(model.notices)
    }

    func testDisplayURL() {
        XCTAssertEqual(OpenSourceLicensesView.display(OSSNotices.sourceRepository), "github.com/Juwan-Hwang/zephyr-mobile")
        XCTAssertEqual(OpenSourceLicensesView.display(URL(string: "http://x.y")!), "http://x.y")
    }
}
