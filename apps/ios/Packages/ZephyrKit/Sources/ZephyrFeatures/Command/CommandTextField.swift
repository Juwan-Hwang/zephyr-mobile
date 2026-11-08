// 指令输入框（原型 `.fld`）：UITextField + 属性文字下划线（REVIEW H-P1-6）。
//
// 取代“透明 TextField + 镜像 Text”：长文本横向滚动时光标与文字不再错位；拼音等 marked text 期间
// 不回写绑定（避免拿拼音字母去请求建议），上屏后再同步；下划线直接画在真实文字上。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

/// 一段需要下划线的字符（按 Character 下标，与 CommandToken.range 同口径）。
struct CommandMark: Equatable {
    var range: Range<Int>
    var color: Color
}

@MainActor
struct CommandTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var marks: [CommandMark]
    var tint: Color
    var placeholder: String
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = FocusingTextField()
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        tf.returnKeyType = .go
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .never
        tf.adjustsFontForContentSizeCategory = true
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.accessibilityLabel = ZL.tr("指令")
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        let traits = tf.traitCollection
        let font = Self.font
        let base = UIColor(ZTokens.Colors.screenT1).resolvedColor(with: traits)
        tf.font = font
        tf.textColor = base
        tf.tintColor = UIColor(tint).resolvedColor(with: traits)
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(ZColor.t3).resolvedColor(with: traits), .font: font])

        // 输入法组合中不动文字（否则会打断拼音）。
        (tf as? FocusingTextField)?.wantsFocus = isFocused
        if tf.markedTextRange == nil {
            let sig = Signature(text: text, marks: marks, dark: colorScheme == .dark, pointSize: font.pointSize)
            if sig != context.coordinator.lastSignature || (tf.text ?? "") != text {
                context.coordinator.lastSignature = sig
                let styled = styledText(font: font, base: base, traits: traits)
                let offset = tf.selectedTextRange.map { tf.offset(from: tf.beginningOfDocument, to: $0.start) }
                tf.attributedText = styled
                if let offset, let pos = tf.position(from: tf.beginningOfDocument, offset: min(offset, styled.length)),
                   tf.isFirstResponder {
                    tf.selectedTextRange = tf.textRange(from: pos, to: pos)
                }
            }
            tf.typingAttributes = [.font: font, .foregroundColor: base]
        }

        if isFocused, !tf.isFirstResponder {
            DispatchQueue.main.async { tf.becomeFirstResponder() }
        } else if !isFocused, tf.isFirstResponder {
            DispatchQueue.main.async { tf.resignFirstResponder() }
        }
    }

    private static var font: UIFont {
        let size = UIFont.preferredFont(forTextStyle: .headline).pointSize
        return UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: size, weight: .regular))
    }

    private func styledText(font: UIFont, base: UIColor, traits: UITraitCollection) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: base])
        let chars = Array(text)
        for m in marks where m.range.lowerBound >= 0 && m.range.upperBound <= chars.count && !m.range.isEmpty {
            let start = String(chars[0..<m.range.lowerBound]).utf16.count
            let len = String(chars[m.range]).utf16.count
            out.addAttributes([
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
                .underlineColor: UIColor(m.color).resolvedColor(with: traits),
            ], range: NSRange(location: start, length: len))
        }
        return out
    }

    struct Signature: Equatable {
        var text: String
        var marks: [CommandMark]
        var dark: Bool
        var pointSize: CGFloat
    }

    /// 窗口就绪后才能成为第一响应者：onAppear 时视图可能还没挂上窗口。
    final class FocusingTextField: UITextField {
        var wantsFocus = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, wantsFocus, !isFirstResponder {
                DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CommandTextField
        var lastSignature: Signature?
        init(_ parent: CommandTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            // marked text（拼音候选）期间不回写，上屏后才同步。
            guard tf.markedTextRange == nil else { return }
            let new = tf.text ?? ""
            if parent.text != new { parent.text = new }
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if tf.markedTextRange != nil { return true }
            parent.onSubmit()
            return false
        }
    }
}
