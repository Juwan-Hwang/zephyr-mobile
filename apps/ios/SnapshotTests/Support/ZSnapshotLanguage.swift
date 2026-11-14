// 快照的界面语言（X-P1-9：英文版快照与伪语言布局测试）。
//
// 测试 bundle 不挂宿主 App，Bundle.main 是 xctest 进程，SwiftUI 的 `Text("中文")`（LocalizedStringKey）
// 与 `ZL.tr` 默认都查不到译文、原样输出中文——这正是现有参考图的语言。
// 英文 / 伪语言变体：渲染期间让 `Bundle.main` 返回一个只含 en.lproj 的临时 bundle（见 ZSnapshotLocalizedBundle），
// `ZL.bundle` 也指向它。中文变体（默认）走原路径，已有参考图不受影响。
//
// 伪语言：在英文译文上加重音字母、按 ~40% 补长并用 ⟦ ⟧ 包起来，用来暴露截断、写死宽度和未走本地化的文案
// （仍显示中文的就是漏网之鱼）。格式占位符（%@ / %lld / %1$@ …）原样保留。

import Foundation
import ObjectiveC
import ZephyrKit

enum ZSnapshotLanguage: String, Sendable, Hashable {
    case zh, en, pseudo

    /// 变体名前缀（中文无前缀，保持现有文件名）。
    var prefix: String { self == .zh ? "" : "\(rawValue)-" }

    var locale: Locale? {
        switch self {
        case .zh: nil
        case .en, .pseudo: Locale(identifier: "en_US")
        }
    }
}

/// 英文 / 伪语言变体的查表：在临时目录拼一个只含 en.lproj 的假 bundle，渲染期间让 `Bundle.main` 返回它。
///
/// #88 前两轮收图：只把 Bundle.main 换类、覆写 `localizedString(forKey:value:table:)` 时 ZL 文案能翻译，
/// SwiftUI 的 `Text("中文")` 仍是中文——SwiftUI 不走这个 ObjC 方法，而是用 CFBundle 直接按 lproj 查表。
/// 所以给它一个真有 lproj 的 bundle：英文变体拷贝测试 bundle 里编出的 en.lproj（含 stringsdict）；
/// 伪语言变体把英文表逐条变换后写成 plist 格式的 Localizable.strings。只有一个本地化，CF 只能选它。
/// `+[NSBundle mainBundle]` 在首次切到非中文时换实现，中文（`override == nil`）时原样返回真 main。
final class ZSnapshotLocalizedBundle {
    nonisolated(unsafe) static var language: ZSnapshotLanguage = .zh
    nonisolated(unsafe) private static var override: Bundle?
    nonisolated(unsafe) private static var cache: [ZSnapshotLanguage: Bundle] = [:]

    private static let englishSource: URL? = {
        Bundle(for: ZSnapshotLocalizedBundle.self).url(forResource: "en", withExtension: "lproj")
    }()

    static var hasEnglish: Bool { englishSource != nil }

    private static let swizzleMain: Void = {
        let selector = NSSelectorFromString("mainBundle")
        guard let method = class_getClassMethod(Bundle.self, selector) else { return }
        typealias Original = @convention(c) (AnyObject, Selector) -> Bundle
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject) -> Bundle = { cls in
            ZSnapshotLocalizedBundle.override ?? original(cls, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }()

    private static func bundle(for language: ZSnapshotLanguage) -> Bundle? {
        if let cached = cache[language] { return cached }
        guard language != .zh, let source = englishSource else { return nil }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("zephyr-snapshot-\(language.rawValue).bundle", isDirectory: true)
        let lproj = root.appendingPathComponent("en.lproj", isDirectory: true)
        try? fm.removeItem(at: root)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            // 真 main 的 Info.plist（UIKit 渲染期间可能读 infoDictionary），开发语言改为 en。
            var info = Bundle.main.infoDictionary ?? [:]
            info["CFBundleDevelopmentRegion"] = "en"
            info["CFBundleLocalizations"] = ["en"]
            (info as NSDictionary).write(to: root.appendingPathComponent("Info.plist"), atomically: true)
            try fm.copyItem(at: source, to: lproj)
            if language == .pseudo {
                for file in (try? fm.contentsOfDirectory(at: lproj, includingPropertiesForKeys: nil)) ?? []
                where file.pathExtension == "strings" {
                    guard let table = NSDictionary(contentsOf: file) as? [String: String] else { continue }
                    let pseudo = table.mapValues(ZPseudo.transform)
                    try? fm.removeItem(at: file)
                    (pseudo as NSDictionary).write(to: file, atomically: true)
                }
                for file in (try? fm.contentsOfDirectory(at: lproj, includingPropertiesForKeys: nil)) ?? []
                where file.pathExtension == "stringsdict" {
                    guard let table = NSDictionary(contentsOf: file) as? [String: Any] else { continue }
                    let pseudo = table.mapValues(ZPseudo.transformPluralEntry)
                    try? fm.removeItem(at: file)
                    (pseudo as NSDictionary).write(to: file, atomically: true)
                }
            }
        } catch {
            return nil
        }
        let bundle = Bundle(url: root)
        cache[language] = bundle
        return bundle
    }

    /// 切换语言；返回之前的语言，调用方负责恢复。
    @MainActor @discardableResult
    static func use(_ language: ZSnapshotLanguage) -> ZSnapshotLanguage {
        let previous = Self.language
        if language == .zh {
            override = nil
            ZL.bundle = nil
        } else {
            _ = swizzleMain
            let fake = bundle(for: language)
            override = fake
            ZL.bundle = fake
        }
        Self.language = language
        return previous
    }
}

enum ZPseudo {
    private static let accents: [Character: Character] = [
        "a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "y": "ý", "c": "ç", "n": "ñ",
        "A": "Å", "E": "É", "I": "Í", "O": "Ö", "U": "Ü", "Y": "Ý", "C": "Ç", "N": "Ñ",
    ]

    /// 占位符：%%、%@、%lld、%d、%.1f、%1$@、stringsdict 变量 %#@count@ 等。
    private static let placeholder = try! NSRegularExpression(pattern: #"%(?:%|#@\w+@|(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@a-zA-Z])"#)

    static func transform(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        let ns = s as NSString
        var out = ""
        var cursor = 0
        var letters = 0
        for m in placeholder.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let plain = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            out += accent(plain, letters: &letters)
            out += ns.substring(with: m.range)
            cursor = m.range.location + m.range.length
        }
        out += accent(ns.substring(from: cursor), letters: &letters)
        let pad = String(repeating: "~", count: max(1, Int((Double(letters) * 0.4).rounded(.up))))
        return "⟦\(out)\(pad)⟧"
    }

    /// stringsdict 的一条：变量字典里的复数分支（zero/one/two/few/many/other）逐条变换；
    /// 格式键 NSStringLocalizedFormatKey 与类型键原样保留，变量名不能动。
    static func transformPluralEntry(_ entry: Any) -> Any {
        guard let dict = entry as? [String: Any] else { return entry }
        let branches: Set<String> = ["zero", "one", "two", "few", "many", "other"]
        return dict.reduce(into: [String: Any]()) { out, kv in
            if let variable = kv.value as? [String: Any] {
                out[kv.key] = variable.reduce(into: [String: Any]()) { v, item in
                    if branches.contains(item.key), let text = item.value as? String {
                        v[item.key] = transform(text)
                    } else {
                        v[item.key] = item.value
                    }
                }
            } else {
                out[kv.key] = kv.value
            }
        }
    }

    private static func accent(_ s: String, letters: inout Int) -> String {
        String(s.map { c in
            if c.isLetter { letters += 1 }
            return accents[c] ?? c
        })
    }
}
