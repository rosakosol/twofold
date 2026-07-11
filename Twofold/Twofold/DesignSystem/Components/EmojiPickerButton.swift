//
//  EmojiPickerButton.swift
//  Twofold
//
//  A circular button showing the current emoji that, when tapped, opens the keyboard —
//  switch to the emoji layout with the keyboard's own globe key (the same way Messages/Notes
//  handle single-emoji entry) to pick literally any system emoji, not just a fixed preset row.
//

import SwiftUI
import UIKit

struct EmojiPickerButton: View {
    @Binding var emoji: String
    var size: CGFloat = 44

    var body: some View {
        EmojiTextField(emoji: $emoji)
            .frame(width: size, height: size)
            .background(Theme.cardBackground, in: Circle())
    }
}

/// Restricts input to a single emoji character. There's no public API to force the system
/// keyboard to open directly on the emoji layout, so this relies on the keyboard's globe key.
private struct EmojiTextField: UIViewRepresentable {
    @Binding var emoji: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = emoji
        field.font = .systemFont(ofSize: 22)
        field.textAlignment = .center
        field.tintColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != emoji {
            uiView.text = emoji
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField
        init(_ parent: EmojiTextField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard !string.isEmpty else { return false }
            guard string.count == 1, let character = string.first, character.isEmoji else { return false }
            parent.emoji = string
            textField.text = string
            return false
        }
    }
}

private extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && (firstScalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

#Preview {
    @Previewable @State var emoji = "💛"
    return EmojiPickerButton(emoji: $emoji)
        .padding()
        .background(Theme.backgroundGradient)
}
