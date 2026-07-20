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
        SectionCard {
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

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(countdownLabel(from: context.date))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.subtleInk)
                        .monospacedDigit()
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

    private var streakSubline: String {
        guard let dailyStreak = appModel.dailyStreak, dailyStreak > 0 else { return "Answer today's question together" }
        let longest = appModel.longestDailyStreak ?? dailyStreak
        return "Longest: \(longest) day\(longest == 1 ? "" : "s")"
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

    /// The real "today" boundary the streak/daily-question logic resets on is relative to this
    /// couple's own `connectedAt` (see `Couple.connectedAt`'s doc comment and
    /// `advance_game_session`'s Postgres trigger), not a shared UTC midnight — a couple that
    /// connected mid-day would otherwise get an arbitrary partial first "day" before their very
    /// first daily question could even reset. Mirrors the trigger's own
    /// `floor((now - connectedAt) / 86400)` day-index math exactly, so the client's countdown
    /// always lands on the same instant the backend actually resets at.
    private func countdownLabel(from now: Date) -> String {
        guard let connectedAt = appModel.couple.connectedAt else { return "" }
        let dayLength: TimeInterval = 86400
        let elapsedDays = (now.timeIntervalSince(connectedAt) / dayLength).rounded(.down)
        let nextBoundary = connectedAt.addingTimeInterval((elapsedDays + 1) * dayLength)
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
