// ControllerSocket —— 扩展进程内对 mihomo external-controller-unix 的极简 HTTP/1.1 客户端（只为 closeAll）。
//
// 扩展不链接 Rust 核心（NE 内存上限），mihomo-mobile 的 C ABI 也没有关连接的入口；控制口是 App Group 里的 unix socket，
// 没有 secret（核心生成配置时去掉，§14），所以直接发一条 `DELETE /connections` 即可。
// 契约 §16.a③：网络切换去抖后关掉旧接口上的连接，让 App 立刻重连，而不是挂到超时。App 挂起时也要做，所以放在扩展里。

import Foundation

enum ControllerSocket {
    /// 请求报文（无正文）。
    static func requestBytes(method: String, path: String) -> Data {
        Data("\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }

    /// 状态行里的状态码；解析失败为 nil。
    static func statusCode(_ response: Data) -> Int? {
        guard let text = String(data: response.prefix(64), encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1.") else { return nil }
        return Int(parts[1])
    }

    /// `DELETE /connections`；2xx 为 true。阻塞调用（限时 `timeout` 秒），不要在主线程用。
    @discardableResult
    static func closeAllConnections(socketPath: String, timeout: TimeInterval = 2) -> Bool {
        guard let code = send(requestBytes(method: "DELETE", path: "/connections"), socketPath: socketPath, timeout: timeout) else { return false }
        return (200..<300).contains(code)
    }

    private static func send(_ request: Data, socketPath: String, timeout: TimeInterval) -> Int? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(tv_sec: .init(timeout), tv_usec: .init((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else { return nil }   // sun_path 上限 104 字节（AppGroup.controllerSocketPath）
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let sent = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == request.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 512)
        let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard n > 0 else { return nil }
        return statusCode(Data(buffer[0..<n]))
    }
}
