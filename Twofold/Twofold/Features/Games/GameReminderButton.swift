//
//  GameReminderButton.swift
//  Twofold
//
//  "Send Reminder", everywhere a game is waiting on the other person.
//
//  The four deck games have had this button, in this shape, since `GameCompletionView` was written.
//  The five puzzle games grew their own instead — a plain blue "Nudge <name>" label, five
//  byte-identical copies of it — so the same action looked like two different things depending on
//  which game you happened to be waiting in, and read as a link in one and a button in the other.
//
//  This is the deck games' version, extracted rather than redesigned: it is the one that was
//  already shared, already the more visible of the two, and already says what it does without
//  needing the partner's name to make sense of it.
//
//  It is deliberately not card-coloured *on* a card. `Theme.cardBackground` is what makes it read
//  as raised against the page, and is exactly what makes it disappear inside a `SectionCard`, which
//  is filled with the same colour — so callers put it below their card, not inside one. That is
//  also where `GameCompletionView` has always put it.
//

import SwiftUI

struct GameReminderButton: View {
    /// Owned by the caller, which runs the send — the button only reports it. Swaps the label for a
    /// spinner and refuses further taps while true, so a slow network cannot queue three nudges.
    let isSending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isSending {
                    ProgressView()
                } else {
                    Text("Send Reminder")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(Theme.ink)
            .background(Theme.cardBackground, in: Capsule())
        }
        .disabled(isSending)
    }
}

#Preview("Ready") {
    GameReminderButton(isSending: false) {}
        .padding()
        .background(Theme.backgroundGradient)
}

#Preview("Sending") {
    GameReminderButton(isSending: true) {}
        .padding()
        .background(Theme.backgroundGradient)
}
