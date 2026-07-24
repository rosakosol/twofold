//
//  GameSharedStates.swift
//  Twofold
//
//  Small pieces of UI shared by all four game views — the universal skip affordance and the
//  abandoned/error fallbacks. The mid-game "waiting for partner" state is gone — each partner
//  now walks straight through their own rounds independently; see GameCompletionView for the
//  new end-of-my-rounds waiting state instead.
//

import SwiftUI

/// Content-safety requirement: every prompt must be skippable.
struct SkipButton: View {
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button("Skip", action: action)
            .font(.subheadline)
            .foregroundStyle(Theme.subtleInk)
            .disabled(isDisabled)
    }
}

struct GameAbandonedState: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flag.slash.fill").font(.largeTitle).foregroundStyle(Theme.subtleInk)
            Text("This game was left unfinished.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The "Report a Problem" item in every game screen's overflow menu. Opens the same in-app
/// support form the Settings > Help > Support flow uses (preset to .gameIssue, with the deck and
/// current card attached) — this replaced the old pair of `mailto:` items, which depended on the
/// device having a mail client configured and arrived with no structured context.
struct ReportProblemMenuItem: View {
    @Binding var showingReportSheet: Bool

    var body: some View {
        Button {
            showingReportSheet = true
        } label: {
            Label("Report a Problem", systemImage: "exclamationmark.bubble")
        }
    }
}

/// Paired with `ReportProblemMenuItem` — attach to whichever view hosts the `Menu`.
extension View {
    func gameIssueReportSheet(isPresented: Binding<Bool>, context: @escaping () -> GameIssueContext) -> some View {
        sheet(isPresented: isPresented) {
            SendSupportRequestView(initialCategory: .gameIssue, gameContext: context())
        }
    }
}

/// Flattens the polymorphic round content into the one label + one id a support report needs.
/// `reportID` is the row id in that content type's own table — the thing that actually lets a
/// report be traced back to a specific question in the games admin tables.
extension GameRoundContent {
    var reportID: UUID {
        switch self {
        case .trivia(let question): question.id
        case .moreLikely(let prompt): prompt.id
        case .thisOrThat(let prompt): prompt.id
        case .deepConversation(let topic): topic.id
        }
    }

    var reportText: String {
        switch self {
        case .trivia(let question): question.question
        case .moreLikely(let prompt): prompt.prompt
        case .thisOrThat(let prompt): "\(prompt.optionA) / \(prompt.optionB)"
        case .deepConversation(let topic): topic.topic
        }
    }
}

extension GameSessionStore {
    /// The deck/card context for a report filed from a live game screen. `title` is the deck
    /// name the caller was already given (see `gameDestinationView`); the currently displayed
    /// round supplies the card. On the results screen there's no single current round, so
    /// callers there pass `round: nil` and only deck-level context is sent.
    func gameIssueContext(gameType: GameType, deckTitle: String?, myID: UUID) -> GameIssueContext {
        let round = displayedRound(myID: myID)
        let roundContent = round.flatMap { content(for: $0) }
        return GameIssueContext(
            gameType: gameType.displayName,
            gameTitle: deckTitle,
            deckID: session?.deckID,
            content: roundContent?.reportText,
            contentID: roundContent?.reportID,
            roundNumber: round?.roundNumber,
            sessionID: session?.id
        )
    }
}

/// Stands in for the native back button on every typed game view — those hide the real one
/// (`.navigationBarBackButtonHidden`) and disable the swipe gesture
/// (`.interactivePopGestureDisabled`) while a round is in play, so this is the *only* way back,
/// routed through `GameSessionStore.goBack(myID:)`/a leave-confirmation instead of an instant pop.
struct GameBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
        }
    }
}

/// Paired with `GameBackButton` — shown when the back button is tapped at round 1, where there's
/// no previous round left to revisit. "Leave" abandons the session (see
/// `BackendService.abandonGameSession`); the couple's daily-question RPC and every deck/game
/// entry point already skip abandoned sessions when looking for one to resume, so this always
/// results in a clean fresh start rather than a stuck "unfinished" state.
extension View {
    func gameLeaveConfirmation(isPresented: Binding<Bool>, onLeave: @escaping () -> Void) -> some View {
        alert("Leave game?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive, action: onLeave)
        } message: {
            Text("Your progress on this game will be lost.")
        }
    }
}

struct GameErrorState: View {
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.heartRed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
