//
//  DailyActivityCard.swift
//  Twofold
//
//  Shown at the top of the Games hub — a shared, couple-wide streak (increments the moment
//  either partner answers, see the migration comment on advance_game_session) plus a themed
//  teaser leading into today's question. The destination is an ordinary
//  DiscussBeforeTravellingGameView driven by `is_daily` session id — that view already handles
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
                    Text(appModel.dailyStreak > 0 ? "\(appModel.dailyStreak)-day streak" : "Start a streak")
                        .font(.subheadline.weight(.bold))
                    Group {
                        if appModel.dailyStreak > 0 {
                            Text("Longest: \(appModel.longestDailyStreak) day\(appModel.longestDailyStreak == 1 ? "" : "s")")
                        } else {
                            Text("Answer today's question together")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.countdownLabel(from: context.date))
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
                        Text("Today's Deep Conversation")
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

    @ViewBuilder
    private var dailyDestination: some View {
        if let sessionID = appModel.todaysDailySessionID {
            DiscussBeforeTravellingGameView(sessionID: sessionID)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await appModel.startOrResumeDailyQuestion() }
        }
    }

    private static func countdownLabel(from now: Date) -> String {
        let calendar = Calendar.current
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) else {
            return ""
        }
        let remaining = max(0, Int(midnight.timeIntervalSince(now)))
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
