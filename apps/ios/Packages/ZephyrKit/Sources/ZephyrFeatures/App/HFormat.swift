// H 页面专用的格式化（ZephyrKit/Format 归 K，不在这里改）。纯 Swift，便于单测。

import Foundation
import ZephyrKit

enum HFormat {
    /// 首页订阅行的到期（原型 global.png："周一到期"）：1–6 天内用星期，其余与 `ZFormat.expiry` 一致
    /// （"已到期" / "今天到期" / "26 天后到期"）。订阅页仍用 `ZFormat.expiry` 的"11月9日到期"（subs.png）。
    static func homeExpiry(_ at: Int64, now: Int64, timeZone: TimeZone = .current) -> String {
        guard at > now else { return ZFormat.expiry(at, now: now, timeZone: timeZone) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let a = cal.startOfDay(for: Date(timeIntervalSince1970: Double(at) / 1000))
        let b = cal.startOfDay(for: Date(timeIntervalSince1970: Double(now) / 1000))
        let days = cal.dateComponents([.day], from: b, to: a).day ?? 0
        guard days >= 1, days < 7 else { return ZFormat.expiry(at, now: now, timeZone: timeZone) }
        let wd = cal.component(.weekday, from: a)          // 1 = 周日
        return ZL.s("%@到期", ZFormat.shortWeekdayName(wd))
    }

}
