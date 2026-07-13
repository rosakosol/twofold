//
//  GameResultsView.swift
//  Twofold
//
//  Shown once a session is fully completed (`GameSessionStore.isRevealed`) — every response
//  becomes visible at once, so this gradually reveals each round before showing a type-specific
//  summary: a score comparison for Trivia, "Biggest Match / Most Surprising / Questions to
//  discuss" for the match games, or an interactive talked-about/come-back-later list for Discuss.
//

import SwiftUI

struct GameResultsView: View {
    let gameType: GameType
    let store: GameSessionStore
    let myID: UUID
    let partnerID: UUID
    let myName: String
    let partnerName: String
    let onPlayAnother: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var revealedCount = 0
    @State private var isMarkingDiscussion = false
    @State private var confettiTrigger = false

    private var isFullyRevealed: Bool { revealedCount >= store.rounds.count }

    /// 0...100 — only meaningful for the two match-style games.
    private var matchPercent: Int? {
        guard gameType == .moreLikely || gameType == .thisOrThat, !store.rounds.isEmpty else { return nil }
        let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
        return Int((Double(matches) / Double(store.rounds.count) * 100).rounded())
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(Array(store.rounds.enumerated()), id: \.element.id) { index, round in
                            if index < revealedCount {
                                roundRow(round)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.9)))
                            }
                        }
                    }

                    if isFullyRevealed {
                        summarySection

                        Button(action: onPlayAnother) {
                            Text("Play Another Game")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Theme.primaryButtonGradient, in: Capsule())
                        .foregroundStyle(.white)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            ConfettiBurstView(trigger: confettiTrigger)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            animateReveal()
            appModel.noteReviewMilestone(.firstGameResults)
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch gameType {
        case .travelTrivia:
            let myScore = GameLogic.triviaScore(responses: store.responses, responderID: myID)
            let partnerScore = GameLogic.triviaScore(responses: store.responses, responderID: partnerID)
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "trophy.fill").font(.system(size: 40)).foregroundStyle(Theme.leafGreen)
                Text("You got \(myScore)/\(store.rounds.count), \(partnerName) got \(partnerScore)/\(store.rounds.count)")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
            }
        case .moreLikely, .thisOrThat:
            let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
            VStack(spacing: Theme.Spacing.xs) {
                if let matchPercent {
                    AnswerSimilarityGauge(percent: matchPercent)
                }
                Text("❤️ You matched \(matches) / \(store.rounds.count) answers!")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
            }
        case .discussBeforeTravelling:
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 40)).foregroundStyle(Theme.leafGreen)
                Text("You both shared your thoughts")
                    .font(.title3.weight(.bold))
            }
        }
    }

    // MARK: - Per-round reveal row

    @ViewBuilder
    private func roundRow(_ round: GameSessionRound) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, partnerID: partnerID)
        let matched = gameType != .discussBeforeTravelling && gameType != .travelTrivia
            && mine?.answerValue == partner?.answerValue && mine?.answerValue.isEmpty == false

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(questionText(for: round))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)

            if gameType == .discussBeforeTravelling {
                responseBlock(name: "You", text: mine?.answerValue)
                responseBlock(name: partnerName, text: partner?.answerValue)
                discussionMarkers(round)
            } else {
                HStack {
                    answerChip(name: "You", text: answerText(mine?.answerValue, for: round), tint: Theme.skyBlue)
                    Spacer(minLength: Theme.Spacing.sm)
                    answerChip(name: partnerName, text: answerText(partner?.answerValue, for: round), tint: Theme.heartRed)
                }

                if gameType == .travelTrivia, case let .trivia(question)? = store.content(for: round) {
                    HStack(spacing: 4) {
                        correctnessBadge(label: "You", isCorrect: mine?.isCorrect)
                        correctnessBadge(label: partnerName, isCorrect: partner?.isCorrect)
                    }
                    if let explanation = question.explanation, !explanation.isEmpty {
                        Text(explanation).font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(matched ? Theme.leafGreen.opacity(0.14) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .animation(.easeOut(duration: 0.4), value: matched)
        .overlay(alignment: .topTrailing) {
            if matched {
                MatchCheckmarkBadge()
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    private func answerChip(name: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func correctnessBadge(label: String, isCorrect: Bool?) -> some View {
        Label(label, systemImage: isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(isCorrect == true ? Theme.leafGreen : Theme.heartRed)
    }

    private func responseBlock(name: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func discussionMarkers(_ round: GameSessionRound) -> some View {
        if let status = round.discussionStatus {
            Label(status == .talkedAbout ? "Talked about" : "Come back later", systemImage: status == .talkedAbout ? "checkmark.circle.fill" : "clock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(status == .talkedAbout ? Theme.leafGreen : Theme.subtleInk)
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    mark(round, status: .comeBackLater)
                } label: {
                    Text("Come back later")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.backgroundGradient, in: Capsule())
                }
                Button {
                    mark(round, status: .talkedAbout)
                } label: {
                    Text("Talked about")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                        .foregroundStyle(.white)
                        .background(Theme.leafGreen, in: Capsule())
                }
            }
            .disabled(isMarkingDiscussion)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        switch gameType {
        case .travelTrivia:
            EmptyView()
        case .moreLikely, .thisOrThat:
            let mismatched = GameLogic.mismatchedRounds(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)

            if !mismatched.isEmpty {
                summaryCard(title: "Questions to discuss", emoji: nil) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(mismatched, id: \.id) { round in
                            Text("•  \(questionText(for: round))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        case .discussBeforeTravelling:
            let talkedAbout = store.rounds.filter { $0.discussionStatus == .talkedAbout }.count
            let comeBackLater = store.rounds.filter { $0.discussionStatus == .comeBackLater }.count
            if talkedAbout + comeBackLater < store.rounds.count {
                Text("Mark each topic above as you talk through it.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                Text(comeBackLater > 0
                    ? "Talked about \(talkedAbout) of \(store.rounds.count) topics, with \(comeBackLater) to revisit later."
                    : "You talked through all \(store.rounds.count) topics.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
    }

    private func summaryCard<Content: View>(title: String, emoji: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(emoji.map { "\(title) \($0)" } ?? title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }


    // MARK: - Content resolution

    private func questionText(for round: GameSessionRound) -> String {
        switch store.content(for: round) {
        case .trivia(let question): question.question
        case .moreLikely(let prompt): prompt.prompt
        case .thisOrThat(let prompt): "\(prompt.optionA) or \(prompt.optionB)"
        case .discuss(let topic): topic.topic
        case .none: ""
        }
    }

    private func answerText(_ value: String?, for round: GameSessionRound) -> String {
        guard let value, !value.isEmpty else { return "Skipped" }
        switch store.content(for: round) {
        case .trivia:
            return value
        case .moreLikely:
            if value == myID.uuidString { return "You" }
            if value == partnerID.uuidString { return partnerName }
            return "—"
        case .thisOrThat(let prompt):
            switch value {
            case ThisOrThatChoice.optionA.rawValue: return prompt.optionA
            case ThisOrThatChoice.optionB.rawValue: return prompt.optionB
            default: return "—"
            }
        case .discuss, .none:
            return value
        }
    }

    // MARK: - Actions

    private func mark(_ round: GameSessionRound, status: DiscussionRoundStatus) {
        isMarkingDiscussion = true
        Task {
            await store.markDiscussionRound(round, status: status)
            isMarkingDiscussion = false
        }
    }

    private func animateReveal() {
        for index in 0...store.rounds.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    revealedCount = index + 1
                }
                // A great match deserves a moment — fires once, right as the last round lands.
                if index + 1 >= store.rounds.count, let matchPercent, matchPercent >= 80 {
                    confettiTrigger = true
                }
            }
        }
    }
}

/// A small green checkmark that pops in with a delayed spring once its row lands — separate from
/// the row's own insertion transition so it reads as its own little "match!" beat.
private struct MatchCheckmarkBadge: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.leafGreen)
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(appeared ? 1 : 0.3)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.15)) {
                appeared = true
            }
        }
    }
}
