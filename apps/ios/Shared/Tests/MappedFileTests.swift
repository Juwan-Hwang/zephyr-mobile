// MappedFile：只读 mmap 的内容、长度、prefix 截断、空文件、二进制检测、不存在的文件。

import XCTest

final class MappedFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MappedFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testMapsTextFile() throws {
        let yaml = "mixed-port: 7890\nmode: rule\nproxies: []\n# 中文注释\n"
        let url = try file("config.yaml", Data(yaml.utf8))
        let mapped = try MappedFile(url: url)
        XCTAssertEqual(mapped.url, url)
        XCTAssertEqual(mapped.count, yaml.utf8.count)
        XCTAssertEqual(Data(mapped.bytes), Data(yaml.utf8))
        XCTAssertEqual(mapped.prefix(10), Data("mixed-port".utf8))
        XCTAssertTrue(mapped.looksLikeText)
    }

    func testPrefixClampsToFileSize() throws {
        let url = try file("short.txt", Data("abc".utf8))
        let mapped = try MappedFile(url: url)
        XCTAssertEqual(mapped.prefix(1_000), Data("abc".utf8))
        XCTAssertEqual(mapped.prefix(0), Data())
    }

    func testEmptyFile() throws {
        let url = try file("empty.yaml", Data())
        let mapped = try MappedFile(url: url)
        XCTAssertEqual(mapped.count, 0)
        XCTAssertEqual(mapped.bytes.count, 0)
        XCTAssertEqual(mapped.prefix(16), Data())
        XCTAssertFalse(mapped.looksLikeText, "空配置不算有效文本")
    }

    func testBinaryWithNULIsNotText() throws {
        let url = try file("rules.bin", Data([0x5A, 0x52, 0x00, 0x01, 0x02, 0xFF]))
        XCTAssertFalse(try MappedFile(url: url).looksLikeText)
    }

    func testInvalidUTF8IsNotText() throws {
        let url = try file("latin1.txt", Data([0x61, 0x62, 0xC3, 0x28, 0x63]))
        XCTAssertFalse(try MappedFile(url: url).looksLikeText)
    }

    /// looksLikeText 只看前 512 字节：大文件尾部的二进制不影响判断，也不会整份读入。
    func testLooksLikeTextOnlyInspectsHead() throws {
        var data = Data(repeating: UInt8(ascii: "a"), count: 4096)
        data.append(contentsOf: [0x00, 0x00])
        let mapped = try MappedFile(url: try file("big.yaml", data))
        XCTAssertEqual(mapped.count, 4098)
        XCTAssertTrue(mapped.looksLikeText)
        XCTAssertEqual(mapped.bytes[4096], 0)
    }

    func testLargeFileContentMatches() throws {
        let data = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let mapped = try MappedFile(url: try file("blob", data))
        XCTAssertEqual(mapped.count, data.count)
        XCTAssertEqual(Data(mapped.bytes), data)
    }

    func testMissingFileThrowsENOENT() {
        let url = directory.appendingPathComponent("nope.yaml")
        XCTAssertThrowsError(try MappedFile(url: url)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOENT)
        }
    }

    func testMappingSurvivesFileDeletion() throws {
        let url = try file("config.yaml", Data("mode: rule\n".utf8))
        let mapped = try MappedFile(url: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(mapped.prefix(4), Data("mode".utf8), "映射持有 inode，删除路径后内容仍可读")
    }
}
