// OpenSourceNotices —— 设置 › 关于 › 开源许可 的数据（GPL-3.0 / MPL-2.0 合规，Refs #209）。
//
// 数据源是仓库根由 tools/gen-third-party.sh 生成的两份文件（project.yml 把它们和 LICENSE 原样打进 App 资源）：
//   THIRD_PARTY_NOTICES.md    许可口径 + Rust / Go 依赖表（名称 | 版本 | 许可 …）
//   THIRD_PARTY_LICENSES.txt  按“文本相同”分组的许可原文：
//       ====…（78 个 =）
//       Used by: aead 0.5.2 (Rust), github.com/ajg/form v1.7.1 (Go), …
//       ----…（78 个 -）
//       <原文>
//     未随包附带许可文件的依赖列在 “No license file shipped …: <标签>, …” 一节，
//     其后 “Standard license text: <SPDX>” 各节给出标准全文。
// 这里只做解析，不改写任何文字；依赖升级后重新生成文件即可，App 无需改代码。纯 Foundation，Linux 可测。

import Foundation

public struct OSSComponent: Sendable, Hashable, Identifiable {
    public enum Ecosystem: String, Sendable, Hashable { case rust = "Rust", go = "Go" }

    public var name: String
    public var version: String
    /// 依赖表里的许可表达式（如 “MIT OR Apache-2.0”），原样保留。
    public var license: String
    public var ecosystem: Ecosystem

    public init(name: String, version: String, license: String, ecosystem: Ecosystem) {
        self.name = name
        self.version = version
        self.license = license
        self.ecosystem = ecosystem
    }

    public var id: String { label }
    /// THIRD_PARTY_LICENSES.txt 里的标签：“aead 0.5.2 (Rust)”。
    public var label: String { "\(name) \(version) (\(ecosystem.rawValue))" }
}

public struct OSSNotices: Sendable, Equatable {
    /// 本 App 的源码仓库（README 的 clone 地址）。NOTICES：每个发布版本的对应源码即本仓库对应的 tag。
    public static let sourceRepository = URL(string: "https://github.com/Juwan-Hwang/zephyr-mobile")!
    public static var sourceTags: URL { sourceRepository.appendingPathComponent("tags") }

    public var rust: [OSSComponent] = []
    public var go: [OSSComponent] = []
    /// “Go 标准库与运行时（go1.27.4）：BSD-3-Clause。” → ("go1.27.4", "BSD-3-Clause")
    public var goToolchain: (version: String, license: String)?
    /// NOTICES 许可口径里的 mihomo 链接与版本：(https://github.com/MetaCubeX/mihomo, v1.19.33)。
    public var mihomo: (url: URL, version: String)?
    /// 仓库根 LICENSE（本 App 自有源码）。
    public var appLicense: String = ""

    /// 许可原文分组（去重后的全文）。
    public private(set) var texts: [String] = []
    /// 标签 → texts 下标（同一依赖可有多份，如 LICENSE-MIT + LICENSE-APACHE）。
    public private(set) var textsByLabel: [String: [Int]] = [:]
    /// 未随包附带许可文件的依赖标签。
    public private(set) var missingLabels: Set<String> = []
    /// “Standard license text: <SPDX>” 各节：SPDX → 全文。
    public private(set) var standardTexts: [String: String] = [:]

    public init() {}

    public static func == (a: OSSNotices, b: OSSNotices) -> Bool {
        a.rust == b.rust && a.go == b.go && a.texts == b.texts && a.textsByLabel == b.textsByLabel
            && a.missingLabels == b.missingLabels && a.standardTexts == b.standardTexts && a.appLicense == b.appLicense
            && a.goToolchain?.version == b.goToolchain?.version && a.goToolchain?.license == b.goToolchain?.license
            && a.mihomo?.url == b.mihomo?.url && a.mihomo?.version == b.mihomo?.version
    }

    public var all: [OSSComponent] { rust + go }

    /// 全部依赖里 mihomo 那一行（GPL-3.0）。
    public var mihomoComponent: OSSComponent? { go.first { $0.name == "github.com/metacubex/mihomo" } }

    /// GPL-3.0 全文：mihomo 所在分组（安装包整体按 GPL-3.0 分发，页内单独提供）。
    public var gplText: String? { mihomoComponent.flatMap { licenseTexts(for: $0).first } }

    /// 某依赖的许可全文。缺许可文件的依赖按其许可表达式里出现的 SPDX 取标准全文；仍没有则为空数组（页面显示说明）。
    public func licenseTexts(for c: OSSComponent) -> [String] {
        if let idx = textsByLabel[c.label], !idx.isEmpty { return idx.map { texts[$0] } }
        guard missingLabels.contains(c.label) else { return [] }
        let ids = Self.spdxIdentifiers(in: c.license)
        return standardTexts.keys.sorted().filter { ids.contains($0) }.compactMap { standardTexts[$0] }
    }

    /// 是否属于“未随包附带许可文件”的依赖。
    public func isMissingLicenseFile(_ c: OSSComponent) -> Bool { missingLabels.contains(c.label) }

    /// 按名称或许可过滤（不区分大小写）；空查询返回原列表。
    public static func filter(_ list: [OSSComponent], query: String) -> [OSSComponent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.license.range(of: q, options: .caseInsensitive) != nil
                || $0.version.range(of: q, options: .caseInsensitive) != nil
        }
    }

    /// “(MIT OR Apache-2.0) AND Unicode-3.0” → ["MIT", "Apache-2.0", "Unicode-3.0"]；“MIT/Apache-2.0” 同样拆开。
    static func spdxIdentifiers(in expression: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: "()/,（）；").union(.whitespaces)
        let words = expression.components(separatedBy: separators).filter { !$0.isEmpty }
        return Set(words.filter { !["OR", "AND", "WITH"].contains($0.uppercased()) })
    }

    // MARK: - 解析

    public static func parse(notices: String, licenses: String, appLicense: String = "") -> OSSNotices {
        var out = OSSNotices()
        out.appLicense = appLicense.trimmingCharacters(in: .whitespacesAndNewlines)
        out.parseNotices(notices)
        out.parseLicenses(licenses)
        return out
    }

    private mutating func parseNotices(_ md: String) {
        var section: OSSComponent.Ecosystem?
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                section = line.contains("Rust") ? .rust : line.contains("Go") ? .go : nil
                continue
            }
            if goToolchain == nil, let r = line.range(of: "Go 标准库与运行时（") {
                let rest = line[r.upperBound...]
                if let close = rest.range(of: "）") {
                    let version = String(rest[..<close.lowerBound])
                    var lic = rest[close.upperBound...].trimmingCharacters(in: .whitespaces)
                    if lic.hasPrefix("：") || lic.hasPrefix(":") { lic.removeFirst() }
                    if lic.hasSuffix("。") || lic.hasSuffix(".") { lic.removeLast() }
                    goToolchain = (version, lic.trimmingCharacters(in: .whitespaces))
                }
            }
            if mihomo == nil, let r = line.range(of: "[mihomo](") {
                let rest = line[r.upperBound...]
                if let close = rest.firstIndex(of: ")"), let url = URL(string: String(rest[..<close])) {
                    let after = rest[rest.index(after: close)...]
                    let version = after.split(separator: "`", omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
                    mihomo = (url, version)
                }
            }
            guard let section, line.hasPrefix("|") else { continue }
            let cells = Self.tableCells(line)
            guard cells.count >= 3 else { continue }
            if cells[0].allSatisfy({ $0 == "-" || $0 == ":" }) { continue }   // |---|---|
            if cells[0] == "crate" || cells[0] == "模块" { continue }          // 表头
            let c = OSSComponent(name: cells[0], version: cells[1], license: cells[2], ecosystem: section)
            switch section {
            case .rust: rust.append(c)
            case .go: go.append(c)
            }
        }
    }

    /// Markdown 表格行按未转义的 `|` 拆分（生成器把单元格里的 `|` 写成 `\|`）。
    static func tableCells(_ line: String) -> [String] {
        var cells: [String] = []
        var cur = ""
        var escaped = false
        for ch in line {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "|" { cells.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        cells.append(cur)
        // 行首、行尾的 `|` 产生两个空单元格。
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static let blockRule = String(repeating: "=", count: 78)
    private static let headerRule = String(repeating: "-", count: 78)
    private static let usedByPrefix = "Used by: "
    private static let missingPrefix = "No license file shipped in the package"
    private static let standardPrefix = "Standard license text: "

    private mutating func parseLicenses(_ txt: String) {
        let lines = txt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // 按 78 个 = 的整行切块；第一块是文件头。
        var blocks: [[String]] = []
        var cur: [String]?
        for line in lines {
            if line == Self.blockRule {
                if let cur { blocks.append(cur) }
                cur = []
            } else {
                cur?.append(line)
            }
        }
        if let cur { blocks.append(cur) }

        for block in blocks {
            guard let header = block.first else { continue }
            // 正文：紧跟的 78 个 - 之后的所有行。
            var body: String {
                guard block.count > 1, block[1] == Self.headerRule else { return "" }
                return block.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if header.hasPrefix(Self.usedByPrefix) {
                let text = body
                guard !text.isEmpty else { continue }
                let index: Int
                if let existing = texts.firstIndex(of: text) { index = existing } else { texts.append(text); index = texts.count - 1 }
                for label in Self.labels(String(header.dropFirst(Self.usedByPrefix.count))) {
                    if textsByLabel[label]?.contains(index) != true { textsByLabel[label, default: []].append(index) }
                }
            } else if header.hasPrefix(Self.missingPrefix), let colon = header.range(of: ": ") {
                missingLabels.formUnion(Self.labels(String(header[colon.upperBound...])))
            } else if header.hasPrefix(Self.standardPrefix) {
                let id = header.dropFirst(Self.standardPrefix.count).trimmingCharacters(in: .whitespaces)
                let text = body
                if !id.isEmpty, !text.isEmpty { standardTexts[id] = text }
            }
        }
    }

    /// “a 1.0 (Rust), github.com/x/y v1.2.0 (Go)” → 两个标签。名称与版本里都不含 “, ”。
    static func labels(_ list: String) -> [String] {
        list.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
