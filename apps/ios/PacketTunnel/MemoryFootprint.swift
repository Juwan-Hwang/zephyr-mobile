// MemoryFootprint —— 当前进程的 phys_footprint（jetsam 判定用的就是它）。
// NE 扩展上限约 50 MB；超出即被系统杀掉、VPN 断开。诊断数据经 handleAppMessage 回给 App。

import Darwin

enum MemoryFootprint {
    static func current() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : nil
    }
}
