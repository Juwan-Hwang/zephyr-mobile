// BundledGeodata —— 随扩展打包的地理数据 → mihomo 内核目录（契约 §20、docs/geodata.md；与 Android BundledGeodata 同构）。
//
// 构建期 scripts/bundle-geodata.sh 把 tools/geodata.lock 固定的 geoip.metadb / GeoSite.dat 拷进 PacketTunnel.appex/geodata/。
// 每次 startTunnel、zm_start 之前：内核目录（App Group/core）里还没有同名文件（不分大小写，mihomo 也这样找）就拷进去——
// 首次安装、清过数据、或升级后新增了文件。已有的从不覆盖：mihomo 的 geo-auto-update 或 App 的 seedKernelGeodata 可能放了更新的。
// 每个文件先拷成临时名再改名（rename 在目标已存在时失败，天然不覆盖），中途被 jetsam 杀掉也不会留下半个真名文件；
// 启动时清理上次残留的临时文件。
//
// 内存（NE 上限约 50 MB）：FileManager.copyItem 走 copyfile(3)（APFS 克隆或内核分块拷贝），文件内容不进本进程的堆。

import Foundation

enum BundledGeodata {
    /// appex 里的资源目录名（scripts/bundle-geodata.sh 的 DEST）。
    static let resourceDirectory = "geodata"
    /// 临时文件后缀；扫描内核目录时据此清理崩溃遗留。
    static let tmpSuffix = ".zgtmp"

    struct Result: Equatable, Sendable {
        /// 本次拷入的文件名。
        var copied: [String] = []
        /// 拷贝失败的文件名 → 原因（mihomo 随后会对缺的文件报 `geodata missing:`）。
        var failed: [String: String] = [:]
    }

    /// 打包的地理数据目录；没打包（Debug 构建拉取失败）为 nil。
    static func bundledDirectory(_ bundle: Bundle = .main) -> URL? {
        guard let url = bundle.resourceURL?.appendingPathComponent(resourceDirectory, isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 目录里的文件名（排序；跳过隐藏文件与临时文件）。
    static func names(in dir: URL?, fileManager fm: FileManager = .default) -> [String] {
        guard let dir, let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return items.filter { !$0.hasPrefix(".") && !$0.hasSuffix(tmpSuffix) }.sorted()
    }

    /// `home` 里有没有名为 `name` 的文件（不分大小写，与 mihomo constant.Path.GeoSite() 等的查找一致）。
    static func isPresent(_ name: String, in home: URL, fileManager fm: FileManager = .default) -> Bool {
        guard let items = try? fm.contentsOfDirectory(atPath: home.path) else { return false }
        return items.contains { $0.caseInsensitiveCompare(name) == .orderedSame && !$0.hasSuffix(tmpSuffix) }
    }

    /// `names` 全都在 `home` 里（此时 mihomo 启动不必联网）；`names` 为空为 false（没打包，不能断言齐全）。
    static func allPresent(_ names: [String], in home: URL, fileManager fm: FileManager = .default) -> Bool {
        !names.isEmpty && names.allSatisfy { isPresent($0, in: home, fileManager: fm) }
    }

    /// 把 `source` 里 `home` 还没有的文件拷进 `home`。已有的不动（不读源）；残留临时文件先清掉。
    @discardableResult
    static func installMissing(from source: URL?, into home: URL, fileManager fm: FileManager = .default) -> Result {
        var result = Result()
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        for leftover in (try? fm.contentsOfDirectory(atPath: home.path)) ?? [] where leftover.hasSuffix(tmpSuffix) {
            try? fm.removeItem(at: home.appendingPathComponent(leftover))
        }
        guard let source else { return result }
        for name in names(in: source, fileManager: fm) where !name.contains("/") {
            if isPresent(name, in: home, fileManager: fm) { continue }
            let tmp = home.appendingPathComponent("\(name).\(UUID().uuidString)\(tmpSuffix)")
            let dst = home.appendingPathComponent(name)
            do {
                try fm.copyItem(at: source.appendingPathComponent(name), to: tmp)
                // 改名前再查一次：别的进程（App 的 seedKernelGeodata）刚放进来的文件不覆盖。
                if isPresent(name, in: home, fileManager: fm) {
                    try? fm.removeItem(at: tmp)
                    continue
                }
                try fm.moveItem(at: tmp, to: dst)   // 目标已存在时失败，不覆盖
                result.copied.append(name)
            } catch {
                try? fm.removeItem(at: tmp)
                if !isPresent(name, in: home, fileManager: fm) { result.failed[name] = error.localizedDescription }
            }
        }
        return result
    }

    /// zm_set_geodata_timeout 该用的毫秒数。打包的文件与配置额外要用的（`extra`：geodata-mode 的 GeoIP.dat、IP-ASN 的 ASN.mmdb，
    /// 见 `MihomoBridge.extraGeodataFiles`）都在内核目录里 → 0（只用本地，不碰网络）；否则 -1（恢复 mihomo-mobile 默认 15 s 有界下载）。
    static func timeoutMillis(bundled: [String], extra: [String] = [], home: URL, fileManager fm: FileManager = .default) -> Int64 {
        guard allPresent(bundled, in: home, fileManager: fm),
              extra.allSatisfy({ isPresent($0, in: home, fileManager: fm) }) else { return -1 }
        return 0
    }
}
