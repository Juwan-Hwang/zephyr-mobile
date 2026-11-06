// TunFileDescriptor —— 拿到 NEPacketTunnelFlow 底层 utun 的文件描述符，交给 mihomo 直接读写。
//
// 为什么要 fd：mihomo 的 TUN 栈（system/gvisor）直接 read/write utun fd，比经 packetFlow.readPackets
// 在 Swift 与 Go 之间逐包拷贝快一个量级，且不在 Swift 堆上堆积包缓冲（NE 内存上限约 50 MB）。
//
// 1) KVC：`packetFlow.socket.fileDescriptor` —— 社区公认做法（sing-box、Clash 系 iOS 客户端广泛使用）。
//    这是私有属性，系统升级可能改名：先用 responds(to:) 判断，避免 KVC 抛 NSUnknownKeyException 直接崩溃。
// 2) 回退：遍历本进程 fd，用 getsockopt(SYSPROTO_CONTROL, UTUN_OPT_IFNAME) 找到名字以 "utun" 开头的
//    控制套接字（WireGuard 的做法）。NE 进程里只有我们这一个 utun。

import Foundation
import NetworkExtension

enum TunFileDescriptor {
    /// <sys/kern_control.h> / <net/if_utun.h> 的常量，iOS SDK 未公开导出。
    private static let sysprotoControl: Int32 = 2
    private static let utunOptIfname: Int32 = 2
    private static let ifNameSize = 16

    static func resolve(from flow: NEPacketTunnelFlow) -> Int32? {
        let kvc = viaKVC(flow)
        if let kvc, isUtun(kvc) { return kvc }
        if let scanned = scan() { return scanned }
        return kvc
    }

    static func viaKVC(_ flow: NEPacketTunnelFlow) -> Int32? {
        guard flow.responds(to: NSSelectorFromString("socket")),
              let socket = flow.value(forKey: "socket") as? NSObject,
              socket.responds(to: NSSelectorFromString("fileDescriptor")),
              let number = socket.value(forKey: "fileDescriptor") as? NSNumber
        else { return nil }
        let fd = number.int32Value
        return fd >= 0 ? fd : nil
    }

    static func scan(limit: Int32 = 1024) -> Int32? {
        for fd in 0...limit where isUtun(fd) { return fd }
        return nil
    }

    static func interfaceName(_ fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: ifNameSize)
        var length = socklen_t(buffer.count)
        let rc = buffer.withUnsafeMutableBytes { raw in
            getsockopt(fd, sysprotoControl, utunOptIfname, raw.baseAddress, &length)
        }
        guard rc == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(validatingUTF8: base)
        }
    }

    static func isUtun(_ fd: Int32) -> Bool {
        interfaceName(fd)?.hasPrefix("utun") ?? false
    }
}
