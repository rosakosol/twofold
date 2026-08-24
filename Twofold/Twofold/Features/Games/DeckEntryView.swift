//
//  DeckEntryView.swift
//  Twofold
//
//  The deck-scoped entry choke point — resolves whether there's already a resumable session for
//  this deck (matched on `deckID`, since a couple can have independent sessions for several
//  decks that share the same underlying mechanic) and goes straight to it, starting a fresh one
//  otherwise. Reuses the exact same 4 game views as regular sessions — a deck session is an
//  ordinary GameSession under the hood (see `start_deck_session`), just pre-populated from a
//  curated content subset instead of a random sample of the shared pool.
//

import PostHog
import SwiftUI

struct DeckEntryView: View {
    let deck: GameDeck

    @Environment(AppModel.self) private var appModel
    @State private var errorMessage: String?
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case playing(sessionID: UUID)
    }

    var body: some View {
        Group {
            if let errorMessage {
                errorState(errorMessage)
            } else {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .playing(let sessionID):
                    gameDestination(sessionID: sessionID)
                }
            }
        }
        // Without this, swapping from `ProgressView` to `gameDestination(sessionID:)` — which can
        // itself immediately land on `GameResultsView` if the deck's session is already complete —
        // picks up SwiftUI's default fade/insertion transition, briefly showing the full-bleed
        // background below undersized before it snaps to full width. See the 4 typed game views
        // for the fuller version of this same fix.
        .transition(.identity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        // Only while this view is showing its own content. Once `phase` flips to `.playing`, the
        // game view mounted below owns the nav bar and supplies its own wrapped title as a
        // `.principal` toolbar item — and because this view renders that game *inline* rather than
        // pushing it, both titles otherwise live in the same navigation bar at once. UIKit shows
        // only the principal one, so it looks right, but both stay in the accessibility tree and
        // VoiceOver announces the deck title twice on every game screen.
        .navigationTitle(isShowingGame ? "" : deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await determinePhase() }
        .postHogScreenView("Games: Deck Entry")
    }

    /// True once the game view below has taken over the nav bar — see `.navigationTitle`.
    private var isShowingGame: Bool {
        guard errorMessage == nil else { return false }
        if case .playing = phase { return true }
        return false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.heartRed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await determinePhase() }
            }
            .font(.headline)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func gameDestination(sessionID: UUID) -> some View {
        gameDestinationView(gameType: deck.gameType, sessionID: sessionID, title: deck.title, topic: deck.topic)
    }

    private func determinePhase() async {
        errorMessage = nil
        do {
            let existing = try await BackendService.fetchGameSessions()
            let resumable = existing.first { $0.deckID == deck.id && ($0.status == .active || $0.status == .waitingForPartner) }
            await start(existingSessionID: resumable?.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func start(existingSessionID: UUID?) async {
        do {
            if let existingSessionID {
                phase = .playing(sessionID: existingSessionID)
            } else {
                let newSessionID = try await BackendService.startDeckSession(deckID: deck.id)
                phase = .playing(sessionID: newSessionID)
                Task { await appModel.refreshGameDecks() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
