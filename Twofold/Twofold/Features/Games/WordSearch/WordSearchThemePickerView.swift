//
//  WordSearchThemePickerView.swift
//  Twofold
//
//  Word Search's front door: six themes where every other game type lists decks.
//
//  The lock here is only so the screen can show one and open the paywall instead of starting a call
//  that would be refused. `start_word_search_session` enforces it for real, and is the only
//  enforcement that counts.
//

import SwiftUI

struct WordSearchThemePickerView: View {
    @Environment(AppModel.self) private var appModel

    @State private var starting: WordSearchTheme?
    @State private var route: StartedWordSearch?
    @State private var showingPaywall = false
    @State private var errorMessage: String?
    @State private var records: [GameRecord] = []

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Eight words hidden in the same grid on both your phones. Find them all, then compare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                GameRecordCard(
                    records: records.filter { $0.gameType == .wordSearch },
                    partnerName: appModel.partner.name,
                    formatBest: { PuzzleClock.text($0) }
                )

                ForEach(WordSearchTheme.allCases, id: \.self) { theme in
                    row(theme)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(GameType.wordSearch.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Reloaded every time the screen appears, not once: coming back here after playing is
        // exactly when the numbers have changed.
        .task { records = await BackendService.fetchGameRecords() }
        .navigationDestination(item: $route) { started in
            WordSearchGameView(sessionID: started.id)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    private func row(_ theme: WordSearchTheme) -> some View {
        // The whole game, not the theme. Travel and Love were free while Word Search was on every
        // plan; since 20261111000700 reaching this screen at all is what Premium buys, so a
        // per-theme split would only be a second answer to a question already settled.
        let locked = !isPremium
        return Button {
            if locked { showingPaywall = true } else { start(theme) }
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(theme.blurb)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if starting == theme {
                        ProgressView()
                    } else if locked {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary)
                    } else {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(starting != nil)
        .accessibilityHint(locked ? "Requires Twofold Premium" : "")
    }

    private func start(_ theme: WordSearchTheme) {
        starting = theme
        errorMessage = nil
        Task {
            defer { starting = nil }
            do {
                let session = try await BackendService.startWordSearchSession(theme: theme)
                route = StartedWordSearch(id: session.sessionID)
            } catch {
                errorMessage = "Couldn't start that grid. \(error.localizedDescription)"
            }
        }
    }
}

/// Where a tapped theme leads.
///
/// No `resumed` flag, unlike sudoku's equivalent: a word search shows how many words are already
/// found the moment it opens, so a resumed grid announces itself. Sudoku needed the flag because a
/// resumed puzzle looks exactly like a new one except for a clock that starts at 4:12.
private struct StartedWordSearch: Identifiable, Hashable {
    let id: UUID
}

#Preview {
    NavigationStack { WordSearchThemePickerView() }
        .environment(AppModel())
}
