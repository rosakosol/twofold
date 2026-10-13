//
//  AdultContentSettingsView.swift
//  Twofold
//
//  The switch for 18+ questions (the After Dark topic). Each partner turns it on for themselves,
//  and the decks only exist once both have — the server enforces that (20261113000900); this
//  screen explains it and shows where the other person stands.
//
//  Turning it on is also the age check. Twofold stores no age, so the confirmation below is the
//  person saying they're 18 or over, and it's asked every time rather than remembered.
//

import SwiftUI

struct AdultContentSettingsView: View {
    @Environment(AppModel.self) private var appModel

    /// What the switch shows. Moves ahead of the server while a change is in flight, and snaps back
    /// if the change fails or the age confirmation is declined.
    @State private var isOn = false
    @State private var isSaving = false
    @State private var showingAgeConfirmation = false
    @State private var errorMessage: String?

    private var status: BackendService.AdultContentStatus? { appModel.adultContentStatus }

    private var partnerName: String {
        let name = appModel.couple.partnerB.name
        return name.isEmpty ? "your partner" : name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Toggle("Show 18+ questions", isOn: Binding(
                        get: { isOn },
                        set: { newValue in
                            if newValue {
                                // Not on yet: on only once they've said they're 18 or over.
                                showingAgeConfirmation = true
                            } else {
                                save(false)
                            }
                        }
                    ))
                    .font(.subheadline)
                    .disabled(isSaving || status == nil)

                    Text("Questions about sex and intimacy, in their own After Dark topic. They only appear once you and \(partnerName) have both turned this on, and either of you can turn them off for both of you at any time.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let line = statusLine {
                    SectionCard {
                        Label(line.text, systemImage: line.icon)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }

                // No tier named: After Dark mixes Plus and Premium decks, and each deck shows its own
                // lock in Games. Naming one plan here was wrong the moment a deck moved to the other.
                Text("Nothing in these decks is shown to anyone else, and turning this off removes them from this device.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .background(ScreenBackground())
        .navigationTitle("18+ questions")
        .task {
            await appModel.refreshAdultContentStatus()
            isOn = status?.me ?? false
        }
        .alert("Are you 18 or older?", isPresented: $showingAgeConfirmation) {
            Button("I'm 18 or older") { save(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These questions are about sex and intimacy, and are only for adults.")
        }
    }

    private var statusLine: (text: String, icon: String)? {
        guard let status else { return nil }
        if !status.hasPartner {
            return ("These need both of you. Connect with your partner first.", "person.2")
        }
        switch (status.me, status.partner) {
        case (true, true):
            return ("On for both of you. You'll find them under After Dark in Games.", "checkmark.circle.fill")
        case (true, false):
            return ("Waiting for \(partnerName) to turn it on too.", "hourglass")
        case (false, true):
            return ("\(partnerName) has turned this on.", "moon.stars.fill")
        case (false, false):
            return nil
        }
    }

    private func save(_ newValue: Bool) {
        let previous = isOn
        isOn = newValue
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await appModel.setAdultContentOptIn(newValue)
                isOn = appModel.adultContentStatus?.me ?? newValue
            } catch {
                isOn = previous
                errorMessage = "Couldn't save that. Check your connection and try again."
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        AdultContentSettingsView()
    }
    .environment(AppModel())
}
