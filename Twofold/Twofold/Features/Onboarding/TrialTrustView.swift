//
//  TrialTrustView.swift
//  Twofold
//

import SwiftUI

struct TrialTrustView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var shownRows: Set<Int> = []
    @State private var iconPulsing = false
    /// Its own store, only to learn whether a trial is on offer before promising one. The paywall
    /// after this loads the same offerings again; RevenueCat serves the second from its cache.
    @State private var store = SubscriptionStore()

    struct TimelineRow: Equatable {
        let label: String
        let title: String
        let subtitle: String
        let icon: String
    }

    /// The trial the paywall will offer when it opens, which is Plus, yearly (`PaywallView`'s
    /// default selection). `nil` when there is none for this Apple Account, or no answer yet.
    private var trial: FreeTrialOffer? { store.freeTrial(for: .plus, period: .yearly) }

    /// The rows, built from the real trial rather than fixed at "Day 12" and "Day 14".
    ///
    /// Without a trial, whether because this Apple Account has had one or because nobody could
    /// say, nothing here mentions one. This screen used to promise fourteen free days to everybody,
    /// lapsed subscribers included, a step before a paywall that would charge them on the spot.
    static func timeline(for trial: FreeTrialOffer?) -> [TimelineRow] {
        let today = TimelineRow(
            label: "Today",
            title: "Unlock all Twofold features",
            subtitle: "Track flights, follow journeys and stay connected.",
            icon: "lock.open.fill"
        )
        guard let trial else {
            return [
                today,
                TimelineRow(
                    label: "Anytime",
                    title: "Cancel whenever you like",
                    subtitle: "Manage it in Settings › Apple Account › Subscriptions.",
                    icon: "checkmark.seal.fill"
                ),
            ]
        }
        // Day numbers only when the length is a fixed count of days and leaves room for a
        // reminder two days out. A month-long trial is not "Day 30" in February.
        let reminderLabel: String
        let endLabel: String
        if let days = trial.dayCount, days >= 3 {
            reminderLabel = "Day \(days - 2)"
            endLabel = "Day \(days)"
        } else {
            reminderLabel = "Before it ends"
            endLabel = "After \(trial.duration)"
        }
        return [
            today,
            TimelineRow(label: reminderLabel, title: "We'll send you a reminder that your trial is ending soon", subtitle: "No surprises.", icon: "bell.fill"),
            TimelineRow(label: endLabel, title: "Your membership begins", subtitle: "Cancel anytime before.", icon: "checkmark.seal.fill"),
        ]
    }

    var body: some View {
        Group {
            switch store.loadState {
            // Nothing until the answer is in, so a trial is never promised and then withdrawn.
            case .idle, .loading:
                ZStack {
                    ScreenBackground()
                    ProgressView()
                }
            // A failed load is "no trial known", which gets the plain version, not an error: the
            // paywall next has its own retry for the plans themselves.
            case .loaded, .failed:
                content(trial: trial)
            }
        }
        .task {
            if store.loadState == .idle { await store.loadOfferings() }
        }
    }

    private func content(trial: FreeTrialOffer?) -> some View {
        let timeline = Self.timeline(for: trial)
        return OnboardingScaffold(
            title: trial == nil ? "Everything Twofold can do, for both of you" : "We want you to try Twofold for free",
            centered: true,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Same pulsing GlobeHeart mark as the welcome screen, bookending onboarding.
                    Image("GlobeHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .scaleEffect(iconPulsing ? 1.08 : 1.0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                iconPulsing = true
                            }
                        }

                    VStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(timeline.enumerated()), id: \.offset) { index, row in
                            timelineRow(row)
                                .opacity(shownRows.contains(index) ? 1 : 0)
                                .offset(x: shownRows.contains(index) ? 0 : -16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        for index in timeline.indices {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.15 + Double(index) * 0.15)) {
                                _ = shownRows.insert(index)
                            }
                        }
                    }

                    // Says what is certainly true — cancel before it ends and nothing is charged —
                    // rather than when access stops, which is not established. An earlier version
                    // claimed access ended immediately on cancelling during a trial, read off a
                    // sandbox subscription: sandbox compresses a fourteen-day trial to about four
                    // minutes, so what looked like a trial cancellation was an ordinary paid period
                    // ending on schedule. One `Text` rather than two so the sentences share their
                    // styling and cannot drift apart.
                    if trial != nil {
                        Text("We'll remind you before your free trial ends. Cancel any time before then and you won't be charged.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            // The centred scaffold otherwise offers it one line and it truncates.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            },
            primaryTitle: trial == nil ? "Continue" : "Continue for free",
            // `.paywall`, not `.saveAccount` — the account screen already happened earlier in
            // the flow (after the widget sell), so going there again looped users back to sign-in.
            primaryAction: { onboarding.path.append(.paywall) }
        )
    }

    private func timelineRow(_ row: TimelineRow) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                Image(systemName: row.icon).foregroundStyle(Theme.accent)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.caption2.weight(.bold)).foregroundStyle(Theme.textSecondary)
                Text(row.title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        TrialTrustView()
    }
    .environment({
        let model = OnboardingModel()
        model.firstName = "You"
        model.partnerName = "Erin"
        model.homeCity = Place.commonCities.first { $0.city == "Melbourne" }
        model.partnerCity = Place.commonCities.first { $0.city == "London" }
        return model
    }())
}
