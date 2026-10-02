//
//  GameResultsView.swift
//  Twofold
//
//  Shown once a session is fully completed (`GameSessionStore.isRevealed`) — every response
//  becomes visible at once, so this gradually reveals each round before showing a type-specific
//  summary: a score comparison for Trivia, "Biggest Match / Most Surprising / Questions to
//  discuss" for the match games, or an interactive talked-about/come-back-later list for Discuss.
//

import PostHog
import SwiftUI

struct GameResultsView: View {
    let gameType: GameType
    let store: GameSessionStore
    let myID: UUID
    let partnerID: UUID
    let myName: String
    let partnerName: String
    let onPlayAnother: () -> Void
    var title: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealedCount = 0
    @State private var confettiTrigger = false
    @State private var isResettingDeck = false
    @State private var resetRoute: SessionRoute?
    /// Set alongside `resetRoute` in `resetDeck(deckID:)` — `SessionRoute` itself only carries
    /// id/gameType, so this rides separately to the `.navigationDestination` closure below.
    @State private var resetTopic: String?
    @State private var showingReportSheet = false
    @State private var showingShare = false

    private var isFullyRevealed: Bool { revealedCount >= store.rounds.count }
    /// A solo session reveals the instant its one real player finishes every round (see
    /// `advance_game_session`'s solo branch) — there's no partner response to ever show, so the
    /// header/summary/per-round chips all need a "your partner hasn't joined yet" framing instead
    /// of a real comparison. More Likely can't reach this at all (blocked server-side solo).
    ///
    /// Checked against this session's own `responses`, not `appModel.partnerConnected` — that
    /// flag is an account-level "are we paired at all" state, not "did my partner actually play
    /// this session," and any transient staleness in it (a refresh landing right as this screen
    /// appears, say) flipped an otherwise-real, both-answered session into showing the solo
    /// "invite your partner" framing even though the partner's answers were sitting right there
    /// in `responses`. A real partner response for this session is a strictly more direct signal.
    private var isSolo: Bool { !store.responses.contains { $0.responderID == partnerID } }

    /// 0...100 — only meaningful for the two match-style games.
    private var matchPercent: Int? {
        guard gameType == .moreLikely || gameType == .thisOrThat, !store.rounds.isEmpty else { return nil }
        let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
        return Int((Double(matches) / Double(store.rounds.count) * 100).rounded())
    }

    var body: some View {
        ZStack {
            // A sibling layer, not a `.background` on this stack.
            //
            // `.background` sizes itself to its *host*, and the host here is a stack whose height
            // and width settle as rounds reveal, the summary appears and the gauge animates. Those
            // layout changes happen inside animated transactions, so the background was carried
            // along with them — visibly narrower than the screen for a beat before settling, which
            // is the flicker this had.
            //
            // The previous attempt at this put `.transaction { $0.animation = nil }` on the
            // gradient. That silences animations originating *within* the gradient, which were
            // never the problem: the gradient was not animating, it was being resized by something
            // else that was. Nothing applied to the background's own content can fix that, because
            // its frame is not its own to decide.
            //
            // As a sibling with its own fill, it takes the stack's full offered size once and stops
            // depending on what the content does.
            ScreenBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                        }
                        .buttonStyle(.twofoldPrimary)
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
        // Fills whatever it is offered, so the stack's size is never a function of its content —
        // which is what kept handing the background a changing frame to follow.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A custom `.principal` item, not just relying on `.navigationTitle` above — an
            // inline nav title is always clamped to one line with a trailing ellipsis, which cut
            // off longer deck titles. This wraps to 2 lines instead; `.navigationTitle` stays
            // (unused visually while this is present) purely so a screen pushed from here still
            // gets a sensible back-button label.
            ToolbarItem(placement: .principal) {
                Text(title ?? gameType.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    // `lineLimit(2)` alone never actually produced two lines: an inline nav bar
                    // offers its principal item a single line's worth of height, so the text took
                    // that proposal and truncated instead of wrapping. `fixedSize` makes it report
                    // the height two lines genuinely need, which is what lets the bar give it the
                    // room.
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isFullyRevealed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share", systemImage: "square.and.arrow.up") {
                        showingShare = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        store.beginEditingAnswers()
                    } label: {
                        Label("Edit My Answers", systemImage: "pencil")
                    }
                    // Only deck-originated sessions know what to restart — every session is
                    // deck-originated now, but older rows from before the shared-pool flow was
                    // removed can still have a nil deckID with no single "this exact game" to
                    // reset back to.
                    if let deckID = store.session?.deckID {
                        Button(role: .destructive) {
                            Task { await resetDeck(deckID: deckID) }
                        } label: {
                            Label("Reset Game", systemImage: "arrow.counterclockwise")
                        }
                    }
                    Divider()
                    ReportProblemMenuItem(showingReportSheet: $showingReportSheet)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isResettingDeck)
            }
        }
        // Post-game: every round is answered, so `displayedRound` is nil and the context
        // carries deck + session but no single "current" card — correct, since a complaint
        // filed here is about the deck/results as a whole rather than one question.
        .gameIssueReportSheet(isPresented: $showingReportSheet) {
            store.gameIssueContext(gameType: gameType, deckTitle: title, myID: myID)
        }
        .sheet(isPresented: $showingShare) {
            GameResultsShareView(data: shareData)
        }
        .navigationDestination(item: $resetRoute) { route in
            gameDestinationView(gameType: route.gameType, sessionID: route.id, topic: resetTopic)
        }
        .onAppear {
            animateReveal()
            // `hasCouple` guard for symmetry with `AppModel.checkReviewMilestones()` — true for
            // solo users too (see its own doc comment), so this still fires for a solo player's
            // first completed game, not just a paired one.
            if appModel.hasCouple {
                appModel.noteReviewMilestone(.firstGameResults)
            }
            if isSolo {
                appModel.noteSoloActionCompleted()
            }
            // `AppModel.gameDecks`/`deckProgress` are cached for the whole app session and only
            // ever refreshed explicitly (see `loadGameDecksIfNeeded()`'s doc comment) — without
            // this, the deck list's "Completed" checkmark stayed stale (from whenever it was
            // first loaded) until the app relaunched, even though the session backing this exact
            // screen just completed. The instant local flip below covers "Your turn" the moment
            // this screen appears, rather than however long this fetch takes to land.
            appModel.markDeckProgressMineCompleted(deckID: store.session?.deckID)
            Task { await appModel.refreshGameDecks() }
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        .postHogScreenView("Games: Results")
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // The deck's own curated title (e.g. "Getting to Know You Better") — distinct from
            // `title ?? gameType.displayName`'s nav-bar fallback, this only ever shows a *real*
            // deck title, never the generic game-type name again right underneath itself.
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            gameTypeHeader
        }
    }

    /// The results header (section 6, Games): a card in the game's own gradient, white text, the
    /// two of you, and the number the whole reveal builds up to.
    @ViewBuilder
    private var gameTypeHeader: some View {
        switch gameType {
        // Neither generated game's comparison is a per-round answer table, so each has its own
        // screen rather than a case here. Nothing routes them into this view; these cases keep
        // the switch exhaustive and show an empty header rather than another game's.
        case .sudoku, .wordGuess, .wordSearch, .connectFour:
            EmptyView()
        case .triviaBattle:
            let myScore = GameLogic.triviaScore(responses: store.responses, responderID: myID)
            resultsHeaderCard {
                Image(systemName: "trophy.fill").font(.system(size: 36)).accessibilityHidden(true)
                if isSolo {
                    Text("You got \(myScore) of \(store.rounds.count)")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Invite your partner to play and compare scores.")
                        .font(.subheadline)
                        .opacity(0.92)
                        .multilineTextAlignment(.center)
                } else {
                    let partnerScore = GameLogic.triviaScore(responses: store.responses, responderID: partnerID)
                    AvatarPair(me: appModel.currentUser, partner: appModel.partner, size: 40, isOnColour: true)
                    Text("You got \(myScore) of \(store.rounds.count), \(partnerName) got \(partnerScore) of \(store.rounds.count)")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                }
            }
        case .moreLikely, .thisOrThat:
            if isSolo {
                resultsHeaderCard {
                    Image(systemName: "person.2.fill").font(.system(size: 36)).accessibilityHidden(true)
                    Text("Your answers are saved")
                        .font(.title3.weight(.bold))
                    Text("Invite your partner to see how you match up.")
                        .font(.subheadline)
                        .opacity(0.92)
                        .multilineTextAlignment(.center)
                }
            } else {
                let matches = GameLogic.matchCount(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)
                resultsHeaderCard {
                    if let matchPercent {
                        Text("\(matchPercent)%")
                            .font(.system(size: 56, weight: .bold))
                            .tracking(-1.5)
                        Text("answer similarity")
                            .font(.subheadline.weight(.semibold))
                            .opacity(0.92)
                    }
                    AvatarPair(me: appModel.currentUser, partner: appModel.partner, size: 40, isOnColour: true)
                        .padding(.vertical, Theme.Spacing.xs)
                    Text("You matched \(matches) of \(store.rounds.count) answers")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
            }
        case .deepConversations:
            resultsHeaderCard {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 36)).accessibilityHidden(true)
                if !isSolo {
                    AvatarPair(me: appModel.currentUser, partner: appModel.partner, size: 40, isOnColour: true)
                }
                Text(isSolo ? "You shared your thoughts" : "You both shared your thoughts")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func resultsHeaderCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            content()
        }
        .foregroundStyle(Theme.onFill)
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(gameType.gradient)
                .overlay { BrandHighlight() }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, y: Theme.Shadow.y)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Share

    private var shareData: GameResultShareData {
        let singleRound = store.rounds.count == 1 ? store.rounds[0] : nil
        let isDailyQuestion = store.session?.isDaily == true
        // Every topic from a multi-round Deep Conversations deck, each with both free-text
        // answers — feeds the share sheet's "choose a topic" picker (see
        // `GameResultShareData.deepConversationRounds`'s own doc comment for why this is about
        // *which* exchange to feature, never a match/similarity concept). Excluded for the Daily
        // Question, which already has its one round covered by `singleRoundQuestion` below.
        let deepConversationRounds: [GameResultShareRound]? = {
            guard gameType == .deepConversations, !isDailyQuestion else { return nil }
            return store.rounds.map { round in
                GameResultShareRound(
                    question: questionText(for: round),
                    myAnswer: answerText(store.myResponse(for: round, myID: myID)?.answerValue, for: round),
                    partnerAnswer: answerText(store.partnerResponse(for: round, partnerID: partnerID)?.answerValue, for: round)
                )
            }
        }()

        return GameResultShareData(
            gameType: gameType,
            title: title ?? gameType.displayName,
            isDaily: isDailyQuestion,
            me: appModel.currentUser,
            partner: appModel.partner,
            matchPercent: matchPercent,
            triviaMyScore: gameType == .triviaBattle ? GameLogic.triviaScore(responses: store.responses, responderID: myID) : nil,
            triviaPartnerScore: gameType == .triviaBattle ? GameLogic.triviaScore(responses: store.responses, responderID: partnerID) : nil,
            triviaTotalRounds: gameType == .triviaBattle ? store.rounds.count : nil,
            deepConversationRounds: deepConversationRounds,
            singleRoundQuestion: singleRound.map { questionText(for: $0) },
            myAnswer: singleRound.map { answerText(store.myResponse(for: $0, myID: myID)?.answerValue, for: $0) },
            partnerAnswer: singleRound.map { answerText(store.partnerResponse(for: $0, partnerID: partnerID)?.answerValue, for: $0) },
            dailyStreak: appModel.dailyStreak
        )
    }

    // MARK: - Per-round reveal row

    @ViewBuilder
    private func roundRow(_ round: GameSessionRound) -> some View {
        let mine = store.myResponse(for: round, myID: myID)
        let partner = store.partnerResponse(for: round, partnerID: partnerID)
        // "Success" state for this round's card — driving the green border/tint, the checkmark
        // badge, and the answer-chip colors below. For the match games (This or That, More
        // Likely) that means both partners picked the same answer; for Trivia it means both
        // partners got the question right, since there's no "same answer" concept to match on
        // there. Discuss has neither notion — its rows never turn green.
        let matched: Bool = {
            switch gameType {
            case .thisOrThat, .moreLikely:
                return mine?.answerValue == partner?.answerValue && mine?.answerValue.isEmpty == false
            case .triviaBattle:
                return mine?.isCorrect == true && partner?.isCorrect == true
            case .deepConversations, .sudoku, .wordGuess, .wordSearch, .connectFour:
                return false
            }
        }()

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(questionText(for: round))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                // Clears the "Match" pill in the corner, so a wrapping question's top line sits
                // beside it rather than under it.
                .padding(.trailing, matched ? 76 : 0)

            if gameType == .deepConversations {
                responseBlock(name: "You", text: mine?.answerValue)
                responseBlock(name: partnerName, text: partner?.answerValue, placeholder: isSolo ? "Hasn't joined yet" : "Skipped this one")
            } else {
                HStack {
                    answerChip(name: "You", text: answerText(mine?.answerValue, for: round), tint: matched ? Theme.success : Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.sm)
                    answerChip(name: partnerName, text: answerText(partner?.answerValue, for: round, placeholder: isSolo ? "Hasn't joined yet" : "Skipped"), tint: matched ? Theme.success : Theme.textPrimary)
                }

                if gameType == .triviaBattle, case let .trivia(question)? = store.content(for: round) {
                    HStack(spacing: 4) {
                        correctnessBadge(label: "You", isCorrect: mine?.isCorrect)
                        correctnessBadge(label: partnerName, isCorrect: partner?.isCorrect)
                    }
                    // Whenever it's not the case both got it right, at least one of the answer
                    // chips above isn't showing the correct string — spell it out explicitly
                    // rather than leaving it to be inferred from whichever chip happened to match.
                    if !matched {
                        Text("Correct answer: \(question.correctAnswer)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                    if let explanation = question.explanation, !explanation.isEmpty {
                        Text(explanation).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matched rows on `successBackground`, the rest on `surfaceGradient` (section 6, Games),
        // each with the standard card edge. The "Match" pill says it in words as well.
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            if matched {
                shape.fill(Theme.successBackground)
            } else {
                shape.fill(Theme.surfaceGradient)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.4), value: matched)
        .overlay(alignment: .topTrailing) {
            if matched {
                MatchPill()
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    private func answerChip(name: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func correctnessBadge(label: String, isCorrect: Bool?) -> some View {
        Label(label, systemImage: isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(isCorrect == true ? Theme.success : Theme.error)
            // `Label`'s default accessibility reading is just its text ("You"/partner's name) —
            // the icon alone doesn't carry "correct" vs "incorrect" to VoiceOver, so it's spelled
            // out explicitly here instead.
            .accessibilityLabel("\(label): \(isCorrect == true ? "correct" : "incorrect")")
    }

    private func responseBlock(name: String, text: String?, placeholder: String = "Skipped this one") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(text?.isEmpty == false ? text! : placeholder)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        switch gameType {
        case .triviaBattle, .sudoku, .wordGuess, .wordSearch, .connectFour:
            EmptyView()
        case .moreLikely, .thisOrThat:
            if isSolo {
                summaryCard(title: "Invite your partner", emoji: "💌") {
                    Text("Once they join, you'll both be able to see how your answers compare.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                let mismatched = GameLogic.mismatchedRounds(rounds: store.rounds, responses: store.responses, partnerAID: myID, partnerBID: partnerID)

                if !mismatched.isEmpty {
                    summaryCard(title: "Questions to discuss", emoji: nil) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(mismatched, id: \.id) { round in
                                Text("•  \(questionText(for: round))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                }
            }
        case .deepConversations:
            EmptyView()
        }
    }

    private func summaryCard<Content: View>(title: String, emoji: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(emoji.map { "\(title) \($0)" } ?? title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
    }


    // MARK: - Content resolution

    private func questionText(for round: GameSessionRound) -> String {
        switch store.content(for: round) {
        case .trivia(let question): question.question
        case .moreLikely(let prompt): prompt.prompt
        case .thisOrThat(let prompt): "\(prompt.optionA) or \(prompt.optionB)"
        case .deepConversation(let topic): topic.topic
        case .none: ""
        }
    }

    private func answerText(_ value: String?, for round: GameSessionRound, placeholder: String = "Skipped") -> String {
        guard let value, !value.isEmpty else { return placeholder }
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
        case .deepConversation, .none:
            return value
        }
    }

    // MARK: - Actions

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
        // The stagger is a presentational flourish, not informational — every round's content is
        // available immediately regardless of when it animates in, so Reduce Motion just shows
        // everything at once instead of a shortened/instant version of the same stagger.
        guard !reduceMotion else {
            revealedCount = store.rounds.count
            if let matchPercent, matchPercent >= 80 {
                confettiTrigger = true
            }
            return
        }

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

/// The "Match" status pill, popping in with a delayed spring once its row lands so it reads as its
/// own little beat. Reduce Motion gets it without the spring.
private struct MatchPill: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StatusPill(kind: .success, text: "Match")
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { appeared = true; return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.15)) {
                    appeared = true
                }
            }
    }
}
