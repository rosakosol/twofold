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
    @State private var isEditingAnswers = false
    @State private var isResettingDeck = false
    @State private var resetRoute: SessionRoute?
    /// Set alongside `resetRoute` in `resetDeck(deckID:)` — `SessionRoute` itself only carries
    /// id/gameType, so this rides separately to the `.navigationDestination` closure below.
    @State private var resetTopic: String?
    @State private var showingNoMailAppAlert = false

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
                // Asymmetric on purpose — a full `.lg` top inset here left a lot of dead space
                // above the similarity percentage before scrolling even starts.
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
            }
            ConfettiBurstView(trigger: confettiTrigger)
        }
        // `.transaction { $0.animation = nil }` keeps this pinned to a static, full-bleed frame
        // regardless of any animated transaction elsewhere on screen (the round-reveal spring in
        // `animateReveal()`, the match gauge's arc animation) — without it the background was
        // observed interpolating its own size alongside those, briefly rendering narrower than
        // the screen before settling.
        .background(Theme.backgroundGradient.ignoresSafeArea().transaction { $0.animation = nil })
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await editMyAnswers() }
                    } label: {
                        Label("Edit My Answers", systemImage: "pencil")
                    }
                    // Only deck-originated sessions know what to restart — a regular
                    // shared-pool session (GameEntryView) has no single "this exact game" to
                    // reset back to.
                    if let deckID = store.session?.deckID {
                        Button(role: .destructive) {
                            Task { await resetDeck(deckID: deckID) }
                        } label: {
                            Label("Reset Game", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Divider()
                    SupportMenuItems(userID: myID, context: "\(gameType.displayName) results — session \(store.session?.id.uuidString ?? "unknown")", showingNoMailAppAlert: $showingNoMailAppAlert)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isEditingAnswers || isResettingDeck)
            }
        }
        .noMailAppAlert(isPresented: $showingNoMailAppAlert)
        .navigationDestination(item: $resetRoute) { route in
            gameDestinationView(gameType: route.gameType, sessionID: route.id, topic: resetTopic)
        }
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
            // More breathing room here than the header's other two cases (`Theme.Spacing.md`,
            // not `.xs`) — this is the one number the whole screen is building up to, so it gets
            // real separation from the "You matched" line underneath it.
            VStack(spacing: Theme.Spacing.md) {
                if let matchPercent {
                    similarityPercent(matchPercent)
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

    /// Plain, large percentage — replaced the earlier half-circle gauge (`AnswerSimilarityGauge`),
    /// which read as visually noisy/misaligned against the rest of this screen; the number itself
    /// is the thing worth making big, not an arc around it.
    private func similarityPercent(_ percent: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(percent)%")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(similarityTint(percent))
            Text("answer similarity")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func similarityTint(_ percent: Int) -> Color {
        switch percent {
        case 80...: Theme.leafGreen
        case 50..<80: Theme.skyBlue
        default: Theme.heartRed
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
                // Clears the checkmark badge's corner footprint (24pt badge + 8pt padding on
                // each side) — without this, a full-width-wrapping question's top line renders
                // right under the badge instead of next to it.
                .padding(.trailing, matched ? 36 : 0)

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
        .overlay {
            // The matched tint alone (14% green over the card background) reads as barely
            // different from an unmatched card against the screen's own pale gradient — a
            // visible edge gives it real separation instead of relying on a subtle fill alone.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(matched ? Theme.leafGreen.opacity(0.5) : .clear, lineWidth: 1.5)
        }
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
            // Real names, not "You" — this value is *who got picked*, shown under a chip
            // already labeled "You"/partnerName, so a literal "You" here reads as a confusing
            // duplicate (and is flat-out wrong when it's the partner's chip: "partner picked
            // You" rendering as "You" under partnerName's own label looks like partner picked
            // themselves).
            if value == myID.uuidString { return myName }
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

    /// Deletes my own responses and drops the session back to `active` — the partner's answers
    /// are untouched, so the couple's shared game view naturally shows my unanswered rounds
    /// again (GameSessionStore.isRevealed flips false) without any extra reveal bookkeeping here.
    private func editMyAnswers() async {
        isEditingAnswers = true
        await store.editMyAnswers()
        isEditingAnswers = false
    }

    /// Only ever offered when this session came from a deck (see the toolbar Menu) — abandons
    /// the completed session and starts a fresh one for the same deck, jumping straight into it.
    private func resetDeck(deckID: UUID) async {
        isResettingDeck = true
        if let sessionID = store.session?.id {
            try? await BackendService.abandonGameSession(id: sessionID)
        }
        if let newID = try? await BackendService.startDeckSession(deckID: deckID) {
            await appModel.refreshGameDecks()
            resetTopic = appModel.gameDecks?.first(where: { $0.id == deckID })?.topic
            resetRoute = SessionRoute(id: newID, gameType: gameType)
        }
        isResettingDeck = false
    }

    private func animateReveal() {
        // A brief beat before the first round card, so it doesn't feel like it's fading in
        // simultaneously with the header text above it. The header itself is plain static text
        // now (no entrance animation of its own to wait out).
        let headerSettleDelay = 0.2

        // 0..<count, not 0...count — one entry per round; the old inclusive range ran an extra,
        // pointless final tick (revealedCount past store.rounds.count, gated harmlessly by
        // isFullyRevealed already having flipped true one tick earlier).
        for index in 0..<store.rounds.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + headerSettleDelay + Double(index) * 0.3) {
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
