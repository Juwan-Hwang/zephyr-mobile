// 显示格式化。与原型文案一致：1.8 GB · 86.4 GB · 2.8 MB/s · 195 KB/s · 13,109,802 · 2:14:07 · 2 小时前 · 26 天后到期。
// 十进制单位（1 GB = 10^9 B），与原型和 iOS 设置里的存储显示一致。纯 Swift，不依赖 Locale，Linux 可测。

import Foundation

public enum ZFormat {

    // MARK: 流量

    /// 字节数 → "1.8 GB" / "86.4 GB" / "12.0 GB" / "512 MB" / "38 KB" / "0 B"。
    /// GB / TB 一位小数；MB 小于 100 时一位小数；KB / B 取整。
    public static func bytes(_ b: Int64) -> String {
        let (v, u) = bytesParts(b)
        return "\(v) \(u)"
    }

    /// 拆成数字与单位，给"1.8<small>GB</small>"这类排版。
    public static func bytesParts(_ b: Int64) -> (value: String, unit: String) {
        let x = Double(max(0, b))
        if x >= 1e12 { return (fixed1(x / 1e12), "TB") }
        if x >= 1e9 { return (fixed1(x / 1e9), "GB") }
        if x >= 1e6 { let m = x / 1e6; return (m < 100 ? fixed1(m) : String(Int64(m.rounded())), "MB") }
        if x >= 1e3 { return (String(Int64((x / 1e3).rounded())), "KB") }
        return (String(Int64(x)), "B")
    }

    /// 字节/秒 → ("2.8", "MB/s") / ("195", "KB/s") / ("0", "B/s")。≥ 1 MB/s 一位小数，KB/s 取整。
    public static func rate(_ bps: Int64) -> (value: String, unit: String) {
        let x = Double(max(0, bps))
        if x >= 1e9 { return (fixed1(x / 1e9), "GB/s") }
        if x >= 1e6 { return (fixed1(x / 1e6), "MB/s") }
        if x >= 1e3 {
            let k = Int64((x / 1e3).rounded())
            return k >= 1000 ? ("1.0", "MB/s") : (String(k), "KB/s")
        }
        return (String(Int64(x)), "B/s")
    }

    /// "2.8 MB/s"
    public static func rateString(_ bps: Int64) -> String { let r = rate(bps); return "\(r.value) \(r.unit)" }

    // MARK: 数字

    /// 千分位："13,109,802"（与原型 toLocaleString('en-US') 一致）。
    public static func count(_ n: Int64) -> String {
        let neg = n < 0
        let digits = Array(String(n.magnitude))
        var out: [Character] = []
        out.reserveCapacity(digits.count + digits.count / 3 + 1)
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (neg ? "-" : "") + String(out)
    }

    /// 延迟："38 ms"；nil → "—"；-1 → "超时"。
    public static func latency(_ ms: Int32?) -> String {
        guard let ms else { return "—" }
        return ms < 0 ? ZL.tr("超时") : "\(ms) ms"
    }

    // MARK: 时间

    /// 时长（毫秒）→ "2:14:07"（时:分:秒，分秒补零；不足一小时为 "0:04:07"，计时器宽度稳定）。
    public static func duration(_ ms: Int64) -> String {
        let s = max(0, ms) / 1000
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return "\(h):\(pad2(m)):\(pad2(sec))"
    }

    /// 时间戳（毫秒）相对 now → "刚刚" / "5 分钟前" / "2 小时前" / "3 天前" / "2 小时后" / "26 天后"。
    public static func relative(_ at: Int64, now: Int64 = nowMillis()) -> String {
        let d = now - at
        let a = Int64(d.magnitude)
        let past = d >= 0
        if a < 60_000 { return ZL.tr(past ? "刚刚" : "即将") }
        if a < 3_600_000 { return ZL.f(past ? "%lld 分钟前" : "%lld 分钟后", a / 60_000) }
        if a < 86_400_000 { return ZL.f(past ? "%lld 小时前" : "%lld 小时后", a / 3_600_000) }
        return ZL.f(past ? "%lld 天前" : "%lld 天后", a / 86_400_000)
    }

    /// 到期文案：≥ 7 天 → "26 天后到期"；1–6 天 → "11月9日到期"；当天 → "今天到期"；已过 → "已到期"。
    public static func expiry(_ at: Int64, now: Int64 = nowMillis(), timeZone: TimeZone = .current) -> String {
        if at <= now { return ZL.tr("已到期") }
        let days = dayIndex(at, timeZone) - dayIndex(now, timeZone)
        if days <= 0 { return ZL.tr("今天到期") }
        if days < 7 { return ZL.s("%@到期", monthDay(at, timeZone: timeZone)) }
        return ZL.f("%lld 天后到期", days)
    }

    /// "11月9日"（英文："Nov 9"）
    public static func monthDay(_ at: Int64, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let date = Date(timeIntervalSince1970: Double(at) / 1000)
        let c = cal.dateComponents([.month, .day], from: date)
        let key = "%lld月%lld日"
        let format = ZL.tr(key)
        if format == key { return "\(c.month ?? 0)月\(c.day ?? 0)日" }          // 未翻译（中文）
        return String(format: format, Int64(c.month ?? 0), Int64(c.day ?? 0))
    }

    /// "11月6日 · 星期五"
    public static func dayTitle(_ at: Int64, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let wd = cal.component(.weekday, from: Date(timeIntervalSince1970: Double(at) / 1000))
        return "\(monthDay(at, timeZone: timeZone)) · \(weekdayName(wd))"
    }

    /// 1 = 周日。"周五" / "Fri"。
    public static func shortWeekdayName(_ weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return ZL.tr(names[(weekday - 1 + 7) % 7])
    }

    /// 1 = 周日。"星期五" / "Friday"。
    public static func weekdayName(_ weekday: Int) -> String {
        let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return ZL.tr(names[(weekday - 1 + 7) % 7])
    }

    /// "9:41"。App 运行时（`ZL.bundle` 已设置）遵循系统的 12 / 24 小时设置与语言（"9:41 AM" / "09:41"）；
    /// 单测（`ZL.bundle == nil`）固定为 "H:mm"，输出稳定。
    public static func clock(_ at: Int64, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: Double(at) / 1000)
        if ZL.bundle != nil {
            let f = DateFormatter()
            f.locale = .autoupdatingCurrent
            f.timeZone = timeZone
            f.dateStyle = .none
            f.timeStyle = .short
            return f.string(from: date)
        }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return "\(c.hour ?? 0):\(pad2(Int64(c.minute ?? 0)))"
    }

    public static func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    // MARK: 内部

    static func fixed1(_ x: Double) -> String {
        let t = Int64((x * 10).rounded())
        return "\(t / 10).\(t % 10)"
    }
    static func pad2(_ n: Int64) -> String { n < 10 ? "0\(n)" : "\(n)" }
    static func dayIndex(_ ms: Int64, _ tz: TimeZone) -> Int64 {
        let off = Int64(tz.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000))) * 1000
        let local = ms + off
        return local >= 0 ? local / 86_400_000 : (local - 86_399_999) / 86_400_000
    }
}
