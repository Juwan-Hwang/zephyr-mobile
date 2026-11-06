// MappedFile —— 只读 mmap。
//
// NE 内存预算（约 50 MB）下，任何“大文件”（mihomo 配置、编译后的规则集、GeoIP）都不能整份读入堆：
// mmap 的页是文件背书的干净页，系统可随时回收，不计入 jetsam 的 dirty footprint。
// 扩展里需要窥探配置（校验、取头部字段）时一律用它，而不是 Data(contentsOf:)。

import Foundation

final class MappedFile: @unchecked Sendable {
    let url: URL
    let count: Int
    private let base: UnsafeMutableRawPointer?

    init(url: URL) throws {
        self.url = url
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let size = Int(st.st_size)
        count = size
        if size == 0 {
            base = nil
            return
        }
        let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
        guard let p, p != MAP_FAILED else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOMEM) }
        _ = madvise(p, size, MADV_SEQUENTIAL)
        base = p
    }

    deinit {
        if let base { munmap(base, count) }
    }

    /// 映射内容（只读，生命周期同 self）。
    var bytes: UnsafeRawBufferPointer { UnsafeRawBufferPointer(start: base, count: count) }

    /// 前 n 个字节（拷贝，n 应很小）。
    func prefix(_ n: Int) -> Data {
        guard let base else { return Data() }
        return Data(bytes: base, count: min(n, count))
    }

    /// 是否以 UTF-8 文本开头（粗略校验配置不是二进制垃圾）。
    var looksLikeText: Bool {
        let head = prefix(512)
        guard !head.isEmpty else { return false }
        return !head.contains(0) && String(data: head, encoding: .utf8) != nil
    }
}
