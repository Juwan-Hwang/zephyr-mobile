// 快照的界面语言（X-P1-9：英文版快照与伪语言布局测试）。
//
// 测试 bundle 不挂宿主 App，Bundle.main 是 xctest 进程，SwiftUI 的 `Text("中文")`（LocalizedStringKey）
// 与 `ZL.tr` 默认都查不到译文、原样输出中文——这正是现有参考图的语言。
// 英文 / 伪语言变体：把 Bundle.main 的类换成 `ZSnapshotLocalizedBundle`，查表转到测试 bundle 里编译出的
// en.lproj（project.yml 把 App/Localizable.xcstrings 作为资源编进 ZephyrSnapshotTests），并把 `ZL.bundle`
// 指向 Bundle.main。中文变体（默认）走原路径，已有参考图不受影响。
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

final class ZSnapshotLocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var language: ZSnapshotLanguage = .zh

    private static let english: Bundle? = {
        let host = Bundle(for: ZSnapshotLocalizedBundle.self)
        return host.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    }()

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        switch Self.language {
        case .zh:
            return super.localizedString(forKey: key, value: value, table: tableName)
        case .en:
            return Self.english?.localizedString(forKey: key, value: value ?? key, table: tableName) ?? (value ?? key)
        case .pseudo:
            let en = Self.english?.localizedString(forKey: key, value: value ?? key, table: tableName) ?? (value ?? key)
            return ZPseudo.transform(en)
        }
    }

    /// SwiftUI 解析 `Text("中文")`（LocalizedStringKey）不走三参数的 `localizedString(forKey:value:table:)`：
    /// #88 首轮收图里 ZL 文案已翻译、SwiftUI 字面量仍是中文。iOS 18.4 的四参数重载是 Swift 扩展、不能 override，
    /// 这里在运行时给子类补上 NSBundle 所有 `localizedStringForKey:value:table:<X>:` 四参数选择子
    /// （localizations: / localization: 等），统一转到上面的查表逻辑；中文时转回原实现。
    private static let installFourArgumentLookups: Void = {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(Bundle.self, &count) else { return }
        defer { free(methods) }
        typealias Original = @convention(c) (AnyObject, Selector, NSString?, NSString?, NSString?, AnyObject?) -> NSString
        for i in 0..<Int(count) {
            let method = methods[i]
            let selector = method_getName(method)
            let name = NSStringFromSelector(selector)
            guard name.hasPrefix("localizedStringForKey:value:table:"), name.filter({ $0 == ":" }).count == 4,
                  let types = method_getTypeEncoding(method) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, NSString?, NSString?, NSString?, AnyObject?) -> NSString = { me, key, value, table, extra in
                guard ZSnapshotLocalizedBundle.language != .zh, let bundle = me as? Bundle, let key else {
                    return original(me, selector, key, value, table, extra)
                }
                return bundle.localizedString(forKey: key as String, value: value as String?, table: table as String?) as NSString
            }
            class_addMethod(ZSnapshotLocalizedBundle.self, selector, imp_implementationWithBlock(block), types)
            ZSnapshotLocalizedBundle.patchedSelectors.append(name)
        }
    }()

    nonisolated(unsafe) static var patchedSelectors: [String] = []

    /// 切换语言；返回之前的语言，调用方负责恢复。
    @MainActor @discardableResult
    static func use(_ language: ZSnapshotLanguage) -> ZSnapshotLanguage {
        if language != .zh, !(Bundle.main is ZSnapshotLocalizedBundle) {
            _ = installFourArgumentLookups
            object_setClass(Bundle.main, ZSnapshotLocalizedBundle.self)
        }
        let previous = Self.language
        Self.language = language
        ZL.bundle = language == .zh ? nil : Bundle.main
        return previous
    }

    static var hasEnglish: Bool { english != nil }
}

enum ZPseudo {
    private static let accents: [Character: Character] = [
        "a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "y": "ý", "c": "ç", "n": "ñ",
        "A": "Å", "E": "É", "I": "Í", "O": "Ö", "U": "Ü", "Y": "Ý", "C": "Ç", "N": "Ñ",
    ]

    /// 占位符：%%、%@、%lld、%d、%.1f、%1$@ 等。
    private static let placeholder = try! NSRegularExpression(pattern: #"%(?:%|(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@a-zA-Z])"#)

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

    private static func accent(_ s: String, letters: inout Int) -> String {
        String(s.map { c in
            if c.isLetter { letters += 1 }
            return accents[c] ?? c
        })
    }
}
