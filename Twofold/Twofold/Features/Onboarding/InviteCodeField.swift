//
//  InviteCodeField.swift
//  Twofold
//
//  The invite-code text field, formatting `XXXX-XXXX` as it is typed.
//
//  A `UITextField` rather than SwiftUI's `TextField`, because neither way of formatting a SwiftUI
//  field held up to typing at speed:
//
//  - Rewriting the text from `.onChange` writes the field a second time, in a later update, with a
//    value worked out from the text as it was when the change was seen. A letter typed in between
//    was already in the field by then and the second write replaced it, so codes lost letters.
//  - Formatting in the binding's setter keeps every letter, but a SwiftUI field that is being edited
//    does not show a value its own setter changed: the state said "ABCD-EFGH" and the field went on
//    showing "ABCDEFGH".
//
//  Here the edit is formatted in `shouldChangeCharactersIn`, before UIKit applies it, and the field's
//  text set right there — synchronously, once, with nothing writing it afterwards. Every keystroke
//  starts from what is really in the field.
//

import SwiftUI
import UIKit

struct InviteCodeField: UIViewRepresentable {
    /// Also the field's accessibility label, as a SwiftUI `TextField`'s title is.
    let placeholder: String
    @Binding var code: String
    var textStyle: UIFont.TextStyle = .body
    var isBold = false
    var alignment: NSTextAlignment = .natural

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.text = code
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.textAlignment = alignment
        field.textColor = .label
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        if isBold, let bold = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            field.font = UIFont(descriptor: bold, size: 0)
        } else {
            field.font = base
        }
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        // Only a change from outside — a prefilled or cleared code. Typing has already set both.
        if field.text != code { field.text = code }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InviteCodeField

        init(parent: InviteCodeField) { self.parent = parent }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let typed = current.replacingCharacters(in: swiftRange, with: string)
            let formatted = InviteCode.applyingEdit(typed, to: current)
            field.text = formatted
            parent.code = formatted
            // Always at the end: a code is typed left to right, and every edit can move the dash.
            let end = field.endOfDocument
            field.selectedTextRange = field.textRange(from: end, to: end)
            return false
        }
    }
}
