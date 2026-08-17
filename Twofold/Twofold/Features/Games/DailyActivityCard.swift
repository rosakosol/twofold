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

    var body: some View {
        // The Games hub's one Aurora hero object (rule #3) — the couple's daily streak sits at
        // the very top of the tab, above every flat deck/topic card below it.
        SectionCard(isHeroInDark: true) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().fill(Theme.primaryButtonGradient)
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(streakHeadline)
                        .font(.subheadline.weight(.bold))
                    Text(streakSubline)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }
                // Redacted (not just showing a "0" default) until the first real fetch resolves —
                // otherwise this briefly flashes "Start a streak" before flipping to the real
                // streak count on every cold load, which read as a glitch rather than a loading
                // state.
                .redacted(reason: appModel.dailyStreak == nil ? .placeholder : [])

                Spacer()

                if appModel.partnerConnected {
                    HStack(spacing: -8) {
                        completionAvatar(person: appModel.currentUser, answered: appModel.todaysMyAnswered)
                            .zIndex(1)
                        completionAvatar(person: appModel.partner, answered: appModel.todaysPartnerAnswered)
                    }
                }

                VStack(alignment: .trailing, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdownLabel(from: context.date))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.subtleInk)
                            .monospacedDigit()
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
                    }
                }
            }

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
                        Text(appModel.todaysDailyQuestionText ?? "A new question, just for you two")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(Theme.Spacing.md)
                .background(
                    LinearGradient(colors: [Theme.skyBlue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .task { await appModel.startOrResumeDailyQuestion() }
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
