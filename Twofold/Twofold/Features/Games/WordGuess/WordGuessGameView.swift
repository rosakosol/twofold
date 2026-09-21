//
//  WordGuessGameView.swift
//  Twofold
//
//  The play screen: board, keyboard, and whatever the result turned out to be.
//
//  Keeps the system back button for the same reason sudoku does — every guess is already written to
//  `PuzzleProgressCache`, so leaving costs nothing and there is nothing to confirm.
//

import PostHog
import SwiftUI

struct WordGuessGameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var store: WordGuessGameStore
    @State private var isSendingReminder = false
    /// Natural height of whatever `finishedSection` is showing — the waiting card or the full
    /// comparison. Measured so the finished board can be sized from what is left over rather than
    /// from the screen's width alone; see `content`.
    @State private var finishedSectionHeight: CGFloat = 0
    @State private var showingReminderSent = false
    /// Toggled the moment both results exist. Toggled rather than set, because `ConfettiBurstView`
    /// animates on any *change* of its trigger.
    @State private var confettiTrigger = false
    @State private var celebratedSession: UUID?

    init(sessionID: UUID) {
        _store = State(initialValue: WordGuessGameStore(sessionID: sessionID))
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                GameErrorState(message: message)
                    .padding(Theme.Spacing.lg)
            case .ready:
                content
            }

            // Outside the switch so it is mounted before the board loads — it animates on a change
            // of its trigger, and a burst view that appeared already-true would never see one.
            ConfettiBurstView(trigger: confettiTrigger)
        }
        .navigationTitle(GameType.wordGuess.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Its own back button, not the system one.
        //
        // A notification opens a game through `RootView`'s `fullScreenCover`, which wraps it in a
        // fresh `NavigationStack` — and at the root of a fresh stack there is nothing to pop, so
        // the system back button is simply absent. That left every one of these screens with no
        // way out at all: the only exit was force-quitting the app. `dismiss()` is right in both
        // contexts, popping when pushed and closing the cover when it is the root, which is what
        // the four deck games have always done.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameBackButton(action: { dismiss() })
            }
        }
        .task(id: store.sessionID) {
            await store.load()
            store.startClock()
        }
        // Its own task: `subscribeRealtime()` loops until cancelled, so folding it into the one
        // above would mean the board waited on a stream that never ends.
        .task(id: store.sessionID) { await store.subscribeRealtime() }
        // Both results exist, so the comparison is on screen. `initial: true` covers arriving at a
        // board that was already finished on both sides, which is a first look at the result for
        // whoever finished first and walked away.
        //
        // Only celebrates a board somebody actually solved. Confetti over two misses would be the
        // app congratulating them for losing.
        .onChange(of: store.partnerResult != nil, initial: true) { _, both in
            guard both, celebratedSession != store.sessionID else { return }
            guard store.play?.isSolved == true || store.partnerResult?.solved == true else { return }
            celebratedSession = store.sessionID
            confettiTrigger.toggle()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        // Same counter as the shake, so a repeat of the same bad word is felt again too.
        .sensoryFeedback(.error, trigger: store.rejectionNudge)
        // The other half of a key that feels pressed. `draft` changes on every letter and every
        // backspace, which is exactly the set of taps that should be felt — and nothing else
        // touches it, so a partner's move arriving cannot buzz somebody's thumb.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: store.draft)
        .onDisappear {
            store.stopClock()
            store.stopRealtime()
        }
        .onChange(of: scenePhase) { _, phase in
            // The clock measures time at the board, so backgrounding stops it.
            if phase == .active { store.startClock() } else { store.stopClock() }
        }
        .alert("Reminder Sent", isPresented: $showingReminderSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(appModel.partner.name) has been told their word is waiting.")
        }
        .postHogScreenView("Games: Word Guess")
    }

    /// The tile size for a finished board, given the space and how much of it the card wants.
    ///
    /// A free function rather than inline in the body so it can be tested: the case that matters
    /// is a screen too small to hold both at full size, and that is tedious to stage on a
    /// simulator and trivial to assert on directly.
    static func finishedTileSide(width: CGFloat, height: CGFloat, cardHeight: CGFloat) -> CGFloat {
        // Vertical padding top and bottom, plus the gap between board and card.
        let chrome = Theme.Spacing.md * 3
        let leftOver = height - chrome - cardHeight
        return max(
            minFinishedTileSide,
            min(
                WordGuessBoardView.tileSide(forWidth: width - Theme.Spacing.md * 2),
                WordGuessBoardView.tileSide(forHeight: leftOver)
            )
        )
    }

    /// How small the finished board may get before scrolling takes over instead.
    ///
    /// Five tiles across at this size is about 180pt wide — readable as a record of the game, and
    /// well past the point where shrinking further would be worse than a scroll. Only reached by a
    /// card that is unusually tall: the comparison view, or a large accessibility text size.
    static let minFinishedTileSide: CGFloat = 34

    @ViewBuilder
    private var content: some View {
        if let play = store.play {
            if play.isComplete {
                // Finished: no keyboard, and the comparison card can outgrow the screen, so this
                // half scrolls. It is the one state that isn't trying to fit a fixed board and
                // keyboard into whatever height the phone has.
                //
                // The `GeometryReader` is outside the `ScrollView` on purpose. A scroll view
                // proposes unbounded height to its content, so a reader *inside* one has no
                // height to report and the board would size its tiles off nothing.
                GeometryReader { proxy in
                    // The board takes what is left after the card, not everything the width
                    // allows.
                    //
                    // Sized from width alone, six rows of width/5 tiles came to ~445pt on a 402pt
                    // phone, leaving the finished card a few points short of what it needed — so
                    // the reminder button sat just below the fold and the one action on the screen
                    // had to be scrolled to. Shrinking the tiles a little costs nothing here: the
                    // board is a record of a game already over, not something being played.
                    //
                    // No feedback loop, because the card's height depends on the width it is given
                    // and not on the board, so this settles in one pass. `finishedSectionHeight`
                    // starts at 0, which makes the first pass identical to the old width-only
                    // behaviour before the measurement lands.
                    let side = Self.finishedTileSide(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        cardHeight: finishedSectionHeight
                    )
                    // Still a ScrollView. `WordGuessComparisonView` is the other thing this branch
                    // shows and it can legitimately outgrow any screen, and an accessibility text
                    // size can outgrow the floor above — in both cases scrolling is the right
                    // answer rather than a board crushed to nothing.
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            WordGuessBoardView(
                                play: play,
                                draft: store.draft,
                                isDraftRejected: store.rejection != nil,
                                tileSide: side
                            )

                            finishedSection(play: play)
                                .padding(.horizontal, Theme.Spacing.md)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    finishedSectionHeight = $0
                                }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                playingLayout(play: play)
            }
        }
    }

    /// Board and keyboard sharing the screen's full height between them.
    ///
    /// This used to be a plain `VStack` with a trailing `Spacer`, which meant every point the phone
    /// had spare became dead space under the keyboard rather than a bigger board or bigger keys —
    /// worse the larger the phone, since the keyboard's height was a constant and the board's was
    /// decided entirely by its width.
    ///
    /// Now the keyboard is sized from what's actually available and the board takes the rest. The
    /// board still draws square tiles fitted to whatever box it is handed (see `WordGuessBoardView`),
    /// so a taller box only ever helps it: it stops being the constraint before the width does.
    private func playingLayout(play: WordGuessPlayState) -> some View {
        GeometryReader { proxy in
            // Everything that isn't board or keyboard, taken off the top before either is sized.
            let chrome = Theme.Spacing.sm * 2 + Theme.Spacing.sm * 2 + Self.rejectionRowHeight
            let usable = max(0, proxy.size.height - chrome)
            // Keys grow with the screen, but never below the height they had when this was fixed
            // (a smaller tap target than before would be a regression, not a layout) and never so
            // tall they turn into buttons. 8.5% of the usable height lands near 46 on an SE and
            // near 60 on a Pro Max.
            // The board is width-limited on any ordinary phone — square tiles, five across — so it
            // cannot use height beyond `boardNeeds` however much it is given. Everything past that
            // belongs to the keyboard rather than sitting as dead space between the two.
            //
            // The previous rule handed the keyboard a flat 8.5% of the screen and left the
            // remainder unclaimed, which is why the keys still read as small next to 72pt tiles.
            let widthLimitedTile = WordGuessBoardView.tileSide(forWidth: proxy.size.width - Theme.Spacing.sm * 2)
            let boardNeeds = WordGuessBoardView.boardHeight(forTileSide: widthLimitedTile)
            let keyboardBudget = max(0, usable - boardNeeds)
            // Still floored at the height the keys had when this was fixed, so a small phone gives
            // up keyboard before it gives up tap target. Capped so a tall phone does not turn the
            // bottom third of the screen into three rows of buttons.
            let keyHeight = min(
                76,
                max(WordGuessKeyboardView.defaultKeyHeight, (keyboardBudget - Theme.Spacing.xs * 2) / 3)
            )

            // The tile is the smaller of what the width allows and what the height left over from
            // the keyboard allows, so the board always fits both ways and stays square either way.
            // Width usually wins; height only becomes the binding constraint on a short screen.
            let boardBox = usable - WordGuessKeyboardView.height(forKeyHeight: keyHeight)
            let side = min(
                WordGuessBoardView.tileSide(forWidth: proxy.size.width - Theme.Spacing.sm * 2),
                WordGuessBoardView.tileSide(forHeight: boardBox)
            )

            VStack(spacing: Theme.Spacing.sm) {
                WordGuessBoardView(
                    play: play,
                    draft: store.draft,
                    isDraftRejected: store.rejection != nil,
                    rejectionNudge: store.rejectionNudge,
                    tileSide: min(side, widthLimitedTile)
                )
                // Takes whatever the keyboard doesn't. The board draws at its own measured size
                // and centres inside this, so spare height reads as margin rather than stretching
                // anything out of square.
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                rejectionMessage

                WordGuessKeyboardView(
                    marks: play.keyboardMarks,
                    isEnabled: store.canType,
                    onLetter: { store.type($0) },
                    onBackspace: { store.backspace() },
                    keyHeight: keyHeight
                )
                .padding(.horizontal, Theme.Spacing.sm)
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    /// Kept in one place because `playingLayout` subtracts it before sizing anything and
    /// `rejectionMessage` draws it — two copies of 18 would drift.
    private static let rejectionRowHeight: CGFloat = 18

    /// Shown in the keyboard's place so the board does not jump when a guess is refused, and
    /// reserved even when empty for the same reason.
    @ViewBuilder
    private var rejectionMessage: some View {
        Group {
            if let rejectionText {
                Text(rejectionText)
            } else {
                // A space rather than nothing, so the row keeps its height and the board above it
                // does not move the instant a guess is refused.
                Text(verbatim: " ")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.heartRedText)
        .frame(height: Self.rejectionRowHeight)
        .accessibilityHidden(rejectionText == nil)
    }

    private var rejectionText: LocalizedStringResource? {
        switch store.rejection {
        case .wrongLength:
            LocalizedStringResource(
                "Not enough letters.",
                comment: "Word Guess, shown when a guess is submitted with fewer than five letters."
            )
        // Says which word rather than only that it was repeated — on a board of six rows the
        // duplicate is usually one the player has stopped looking at.
        case .alreadyGuessed:
            LocalizedStringResource(
                "You've already tried \(store.draft.uppercased()).",
                comment: "Word Guess, shown when a word already on the board is submitted again. The value is that word, in capitals."
            )
        case .notAWord:
            LocalizedStringResource(
                "\(store.draft.uppercased()) isn't in the word list.",
                comment: "Word Guess, shown when a guess is not a recognised word. The value is what they typed, in capitals."
            )
        case .boardFinished, .none:
            nil
        }
    }

    @ViewBuilder
    private func finishedSection(play: WordGuessPlayState) -> some View {
        if let theirs = store.partnerResult {
            WordGuessComparisonView(comparison: WordGuessComparison(
                mine: WordGuessSummary(
                    guessCount: play.guesses.count,
                    solved: play.isSolved,
                    elapsed: play.elapsed
                ),
                theirs: theirs,
                partnerName: appModel.partner.name
            ))
        } else {
            waitingCard(play: play)
        }
    }

    private func waitingCard(play: WordGuessPlayState) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            waitingSummary(play: play)

            // Outside the card: `GameReminderButton` is filled with `Theme.cardBackground` so it
            // reads as raised against the page, which is the one colour it would disappear into
            // inside a `SectionCard`. Same placement the deck games use.
            if appModel.hasCouple {
                GameReminderButton(isSending: isSendingReminder, action: remindPartner)
            }
        }
    }

    private func waitingSummary(play: WordGuessPlayState) -> some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                // Glyph beside the result rather than stacked above it. Centred and stacked, the
                // icon cost a whole line of its own and pushed the reminder button below the fold
                // on a board this tall — see `content` for the other half of that fix.
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: play.isSolved ? "checkmark.seal.fill" : "clock.badge.xmark")
                        .font(.title2)
                        .foregroundStyle(play.isSolved ? Theme.leafGreenText : Theme.subtleInk)

                    Text(play.isSolved
                         ? "Got it in \(WordGuessComparison.guessText(play.guesses.count))"
                         : "Out of guesses")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }
                .multilineTextAlignment(.center)

                // The word is told either way. Somebody who missed it and is never shown the answer
                // has been given a puzzle with no ending — and they will find out from their
                // partner anyway, which is a worse way to hear it.
                Text("The word was \(play.answer.uppercased()).")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)

                if appModel.hasCouple {
                    // Shorter than it was ("Your result is saved. You'll see how it compares
                    // once ... has played theirs."), which ran to three lines on a narrow phone
                    // and said twice over what the card already shows by existing.
                    Text("You'll see how it compares once \(appModel.partner.name) has played.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("A new word is waiting tomorrow.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The same `gameReminder` push the other games send, rather than a Word Guess-specific one —
    /// it is the identical situation, and a second notification type saying the same thing is a
    /// second thing to keep in step with the copy.
    private func remindPartner() {
        isSendingReminder = true
        Task {
            await BackendService.notifyPartner(
                event: .gameReminder,
                detail: GameType.wordGuess.displayName,
                sessionID: store.sessionID,
                gameType: .wordGuess
            )
            isSendingReminder = false
            showingReminderSent = true
        }
    }
}
