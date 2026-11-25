// BundledGeodata：打包的地理数据 → 内核目录（契约 §20）。只拷缺的、不覆盖、不分大小写、临时名 + 改名、清理残留。

import XCTest

final class BundledGeodataTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("geodata-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("bundle/geodata", isDirectory: true)
        home = root.appendingPathComponent("core", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("metadb".utf8).write(to: source.appendingPathComponent("geoip.metadb"))
        try Data("geosite".utf8).write(to: source.appendingPathComponent("GeoSite.dat"))
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func read(_ name: String) throws -> String { try String(contentsOf: home.appendingPathComponent(name), encoding: .utf8) }
    private func listing() -> [String] { ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).sorted() }

    func testCopiesMissingFiles() throws {
        let r = BundledGeodata.installMissing(from: source, into: home)
        XCTAssertEqual(r.copied, ["GeoSite.dat", "geoip.metadb"])
        XCTAssertTrue(r.failed.isEmpty)
        XCTAssertEqual(try read("geoip.metadb"), "metadb")
        XCTAssertEqual(try read("GeoSite.dat"), "geosite")
        XCTAssertEqual(listing(), ["GeoSite.dat", "geoip.metadb"], "不留临时文件")
        // 第二次：全都在，什么都不拷
        XCTAssertEqual(BundledGeodata.installMissing(from: source, into: home).copied, [])
    }

    func testNeverOverwritesExistingFileCaseInsensitive() throws {
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        // mihomo 的 geo-auto-update 或 App 的 seedKernelGeodata 已放了更新的（文件名大小写可能不同）
        try Data("newer".utf8).write(to: home.appendingPathComponent("geosite.dat"))
        let r = BundledGeodata.installMissing(from: source, into: home)
        XCTAssertEqual(r.copied, ["geoip.metadb"])
        XCTAssertEqual(try read("geosite.dat"), "newer")
        XCTAssertEqual(listing().count, 2, "没有再拷一份 GeoSite.dat")
    }

    func testRemovesLeftoverTempFiles() throws {
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let leftover = home.appendingPathComponent("GeoSite.dat.1234\(BundledGeodata.tmpSuffix)")
        try Data("half".utf8).write(to: leftover)
        BundledGeodata.installMissing(from: nil, into: home)
        XCTAssertFalse(fm.fileExists(atPath: leftover.path))
        XCTAssertFalse(BundledGeodata.isPresent("GeoSite.dat", in: home), "临时文件不算已存在")
    }

    func testFailedCopyLeavesNoResidue() throws {
        // 内核目录只读：copyItem 必然失败，不应留下真名或临时名
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: home.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home.path) }
        let r = BundledGeodata.installMissing(from: source, into: home)
        XCTAssertTrue(r.copied.isEmpty)
        XCTAssertEqual(Set(r.failed.keys), ["GeoSite.dat", "geoip.metadb"])
        XCTAssertEqual(listing(), [])
    }

    func testNamesSkipHiddenAndTemp() throws {
        try Data().write(to: source.appendingPathComponent(".DS_Store"))
        try Data().write(to: source.appendingPathComponent("x\(BundledGeodata.tmpSuffix)"))
        XCTAssertEqual(BundledGeodata.names(in: source), ["GeoSite.dat", "geoip.metadb"])
        XCTAssertEqual(BundledGeodata.names(in: nil), [])
    }

    func testTimeoutZeroOnlyWhenEverythingIsLocal() throws {
        let bundled = BundledGeodata.names(in: source)
        XCTAssertEqual(BundledGeodata.timeoutMillis(bundled: bundled, home: home), -1, "还没拷：保留默认有界下载")
        BundledGeodata.installMissing(from: source, into: home)
        XCTAssertEqual(BundledGeodata.timeoutMillis(bundled: bundled, home: home), 0, "齐全：只用本地")
        XCTAssertEqual(BundledGeodata.timeoutMillis(bundled: bundled, extra: ["GeoIP.dat"], home: home), -1, "geodata-mode 还要 GeoIP.dat")
        try Data("dat".utf8).write(to: home.appendingPathComponent("GeoIP.dat"))
        XCTAssertEqual(BundledGeodata.timeoutMillis(bundled: bundled, extra: ["GeoIP.dat"], home: home), 0)
        XCTAssertEqual(BundledGeodata.timeoutMillis(bundled: [], home: home), -1, "没打包：不能断言齐全")
    }
}
