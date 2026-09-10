//
//  DailyActivityCard.swift
//  Twofold
//
//  Shown at the top of the Games hub — a shared, couple-wide streak (increments the moment
//  either partner answers, see the migration comment on advance_game_session) plus a themed
//  teaser leading into today's question. The destination is an ordinary
//  DeepConversationsGameView driven by `is_daily` session id — that view already handles
//  every session state (fresh/in-progress/waiting-on-partner/revealed) via GameSessionStore, so
//  this card's only job is getting the user to the right session id, not re-deriving that state.
//

import SwiftUI

struct DailyActivityCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One line of `.caption2`, measured. Both the question teaser and the streak subline reserve
    /// two of these so their height stops depending on what the text happens to say — which is the
    /// whole reason the card used to jump.
    @ScaledMetric(relativeTo: .caption2) private var captionLineHeight: CGFloat = 13.5

    /// A skeleton is only right before there's anything to show. `startOrResumeDailyQuestion()`
    /// runs on every appearance of this card, so keying purely off the in-flight flag would flash
    /// placeholder bars over a question that's already on screen every time the tab is revisited.
    private var isLoadingQuestion: Bool {
        appModel.isLoadingDailyQuestion && appModel.todaysDailyQuestionText == nil
    }

    /// Two lines' worth, so a one-line question and a two-line one occupy the same space and
    /// nothing below shifts when the real text replaces the skeleton. Left unreserved at
    /// accessibility sizes, where the teaser is allowed to run to whatever length it needs.
    private var reservedCaptionHeight: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : captionLineHeight * 2
    }

    /// Stand-in text for the skeleton. Never read: `.redacted` replaces it with bars, and the
    /// accessibility label below says what's actually happening. It exists only to give the
    /// placeholder two lines to draw.
    private static let questionSkeletonText = "Loading today's question for the two of you"


    var body: some View {
        // The Games hub's one Aurora hero object (rule #3) — the couple's daily streak sits at
        // the very top of the tab, above every flat deck/topic card below it.
        SectionCard(isHeroInDark: true) {
            streakSummary

            NavigationLink {
                dailyDestination
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    ShimmeringGlobeHeart()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Deep Question")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(appModel.todaysDailyQuestionText
                            ?? (isLoadingQuestion ? Self.questionSkeletonText : "A new question, just for you two"))
                            .font(.caption2)
                            // 0.85 landed at 4.46:1 against the deepened banner — just under AA.
                            // 0.92 reads the same as a softened white and clears it at 4.9:1.
                            .foregroundStyle(.white.opacity(0.92))
                            // Two lines is right at normal sizes — this is a teaser, and the full
                            // question is one tap away. At accessibility sizes two lines isn't
                            // enough to reach the end of any real question, so the teaser became a
                            // fragment; let it run instead.
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            // Reserved before the text arrives and kept afterwards, so the card is
                            // the same height whether it's showing bars, a one-line question or a
                            // two-line one. Without this the teaser went from the short generic
                            // line to a wrapped real question and pushed every deck below it down.
                            .frame(minHeight: reservedCaptionHeight, alignment: .topLeading)
                            .redacted(reason: isLoadingQuestion ? .placeholder : [])
                            .accessibilityLabel(isLoadingQuestion ? Text("Loading today's question") : Text(appModel.todaysDailyQuestionText ?? "A new question, just for you two"))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(Theme.Spacing.md)
                .background(
                    // `skyBlueText`, not `skyBlue`: this banner is white text on a full-bleed
                    // fill, and white on the fill blue measures 2.60:1 in light mode and 1.70:1 in
                    // dark — the indigo end was fine (5.65:1), so only the top of the gradient was
                    // failing. The deepened token is exactly what Theme.swift keeps for this case.
                    LinearGradient(colors: [Theme.skyBlueText, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .task { await appModel.startOrResumeDailyQuestion() }
    }

    /// Flame, streak wording, both partners' answered-today ticks and the countdown, all on one
    /// row. That row only works while the four of them fit side by side: at accessibility text
    /// sizes each got roughly a quarter of the card and the words came apart mid-syllable —
    /// "Start a strea / k", "An- / swer to / day's". Above that threshold the row splits in two,
    /// which gives each half the full width and keeps every phrase whole.
    @ViewBuilder
    private var streakSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    flameBadge
                    streakText
                }
                HStack(spacing: Theme.Spacing.sm) {
                    answeredAvatars
                    Spacer(minLength: Theme.Spacing.sm)
                    countdownBlock
                }
            }
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                flameBadge
                streakText
                Spacer()
                answeredAvatars
                countdownBlock
            }
        }
    }

    private var flameBadge: some View {
        ZStack {
            Circle().fill(Theme.primaryButtonGradient)
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    private var streakText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(streakHeadline)
                .font(.subheadline.weight(.bold))
            Text(streakSubline)
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
                // Same reservation as the teaser: this line swings between "Answer today's
                // question together" and "Keep it going" depending on whether a streak is running,
                // and in this narrow column that's a two-line/one-line difference.
                .frame(minHeight: reservedCaptionHeight, alignment: .topLeading)
        }
        // Redacted (not just showing a "0" default) until the first real fetch resolves —
        // otherwise this briefly flashes "Start a streak" before flipping to the real
        // streak count on every cold load, which read as a glitch rather than a loading
        // state.
        .redacted(reason: appModel.dailyStreak == nil ? .placeholder : [])
    }

    @ViewBuilder
    private var answeredAvatars: some View {
        if appModel.partnerConnected {
            HStack(spacing: -8) {
                completionAvatar(person: appModel.currentUser, answered: appModel.todaysMyAnswered)
                    .zIndex(1)
                completionAvatar(person: appModel.partner, answered: appModel.todaysPartnerAnswered)
            }
        }
    }

    private var countdownBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownLabel(from: context.date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
                    .monospacedDigit()
                    // A countdown that wraps ("Next in 05:1 / 4:22") is unreadable, and it has a
                    // known maximum width, so it keeps its natural one rather than being squeezed.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // Sits under the countdown rather than in `streakSubline` (where it used to
            // live) because that line only ever renders once a streak is actually running
            // — so the couple's best-ever streak, the one number worth chasing, was
            // invisible in exactly the state where it's most motivating: right after a
            // streak lapses and the subline reverts to "Answer today's question together".
            if let best = appModel.longestDailyStreak, best > 0 {
                Text("Best: \(best) day\(best == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// Placeholder text while `appModel.dailyStreak` is nil — never actually shown (the whole
    /// block is `.redacted` in that state), just needs to occupy roughly the right width/shape.
    private var streakHeadline: String {
        guard let dailyStreak = appModel.dailyStreak else { return "Start a streak" }
        return dailyStreak > 0 ? "\(dailyStreak)-day streak" : "Start a streak"
    }

    /// No longer carries the longest streak — that moved out to its own line under the countdown
    /// (see above), so this can stay a plain call to action in both states.
    private var streakSubline: String {
        guard let dailyStreak = appModel.dailyStreak, dailyStreak > 0 else { return "Answer today's question together" }
        // Deliberately short: the headline above already says "N-day streak", and the row now also
        // carries the countdown plus "Best: N days" on the right, so a longer line here wrapped to
        // three lines and crowded the card.
        return "Keep it going"
    }

    @ViewBuilder
    private var dailyDestination: some View {
        if let sessionID = appModel.todaysDailySessionID {
            DeepConversationsGameView(sessionID: sessionID)
        } else if let error = appModel.dailyQuestionError {
            VStack(spacing: Theme.Spacing.md) {
                GameErrorState(message: error)
                Button("Try again") {
                    Task { await appModel.startOrResumeDailyQuestion() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await appModel.startOrResumeDailyQuestion() }
        }
    }

    /// A small avatar with a green checkmark badge once that person has answered today's
    /// question — the two overlap slightly (see the `-8` spacing above) so they read as one
    /// "who's done" glance rather than two separate, unrelated icons.
    private func completionAvatar(person: Person, answered: Bool) -> some View {
        AvatarView(person: person, size: 26, showsRing: true)
            .overlay(alignment: .bottomTrailing) {
                if answered {
                    ZStack {
                        Circle().fill(Theme.leafGreen)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
            }
    }

    /// Counts down to the boundary the backend actually resets on, taken straight from
    /// `get_daily_streak` rather than re-derived here. This used to recompute it locally from
    /// `couple.connectedAt` — correct while the day was anchored to pairing time, but silently
    /// wrong the moment 20260908000000 moved the real boundary to local midnight, leaving the
    /// timer counting down to a moment nothing happened at. For a couple the boundary depends on
    /// *both* partners' timezones (the later of the two midnights), which the client has no
    /// business reconstructing.
    private func countdownLabel(from now: Date) -> String {
        guard let nextBoundary = appModel.dailyStreakResetsAt else { return "" }
        let remaining = max(0, Int(nextBoundary.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "Next in %02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// A soft diagonal highlight sweeps across the globe-heart mark every few seconds, then pauses —
/// a quick "sweep, rest" cadence rather than a continuous back-and-forth, so it reads as a
/// periodic glint rather than competing for attention with the text next to it.
private struct ShimmeringGlobeHeart: View {
    @State private var sweepIsAcross = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("GlobeHeart")
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.95), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geo.size.width * 0.55)
                    .rotationEffect(.degrees(24))
                    .offset(x: sweepIsAcross ? geo.size.width * 1.3 : -geo.size.width * 1.3)
                }
                .mask(Image("GlobeHeart").resizable().scaledToFit())
            }
            .task {
                // Purely decorative, no information in the sweep itself — skip the repeating
                // loop entirely under Reduce Motion, leaving the static mark.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 1.1)) {
                        sweepIsAcross = true
                    }
                    try? await Task.sleep(for: .seconds(1.1))
                    sweepIsAcross = false
                    try? await Task.sleep(for: .seconds(1.8))
                }
            }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            DailyActivityCard()
                .padding()
        }
        .background(Theme.backgroundGradient)
    }
    .environment(AppModel())
}
